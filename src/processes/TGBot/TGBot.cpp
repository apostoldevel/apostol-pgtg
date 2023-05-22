/*++

Program name:

  tgpg

Module Name:

  TGBot.cpp

Notices:

  Process: Telegram bot

Author:

  Copyright (c) Prepodobny Alen

  mailto: alienufo@inbox.ru
  mailto: ufocomp@gmail.com

--*/

#include "Core.hpp"
#include "TGBot.hpp"
//----------------------------------------------------------------------------------------------------------------------

#define CONFIG_SECTION_NAME "process/TGBot"
#define SLEEP_SECOND_AFTER_ERROR 10
#define PG_LISTEN_NAME "tg_bot"
//----------------------------------------------------------------------------------------------------------------------

extern "C++" {

namespace Apostol {

    namespace Processes {

        CBotHandler::CBotHandler(CTGBot *AModule, const CString &Data, COnBotHandlerEvent && Handler):
                CPollConnection(AModule->ptrQueueManager()), m_Allow(true) {

            m_TimeOut = 0;
            m_TimeOutInterval = 15000;

            m_pModule = AModule;
            m_Payload = Data;
            m_Handler = Handler;

            AddToQueue();
        }
        //--------------------------------------------------------------------------------------------------------------

        CBotHandler::~CBotHandler() {
            RemoveFromQueue();
        }
        //--------------------------------------------------------------------------------------------------------------

        void CBotHandler::Close() {
            m_Allow = false;
            RemoveFromQueue();
        }
        //--------------------------------------------------------------------------------------------------------------

        int CBotHandler::AddToQueue() {
            return m_pModule->AddToQueue(this);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CBotHandler::RemoveFromQueue() {
            m_pModule->RemoveFromQueue(this);
        }
        //--------------------------------------------------------------------------------------------------------------

        bool CBotHandler::Handler() {
            if (m_Allow && m_Handler) {
                m_Handler(this);
                return true;
            }
            return false;
        }

        //--------------------------------------------------------------------------------------------------------------

        //-- CTGBot ----------------------------------------------------------------------------------------------------

        //--------------------------------------------------------------------------------------------------------------

        CTGBot::CTGBot(CCustomProcess *AParent, CApplication *AApplication):
                inherited(AParent, AApplication, "telegram bot") {

            m_CheckDate = 0;
            m_CallDate = 0;

            m_Progress = 0;
            m_MaxQueue = Config()->PostgresPollMin();

            m_HeartbeatInterval = 5000;

            m_Status = psStopped;
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::BeforeRun() {
            Application()->Header(Application()->Name() + ": telegram bot");

            Log()->Debug(APP_LOG_DEBUG_CORE, MSG_PROCESS_START, GetProcessName(), Application()->Header().c_str());

            InitSignals();

            Reload();

            SetUser(Config()->User(), Config()->Group());

            InitializePQClients(Application()->Title(), 1, Config()->PostgresPollMin());

            SigProcMask(SIG_UNBLOCK);

            SetTimerInterval(1000);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::AfterRun() {
            CApplicationProcess::AfterRun();
            PQClientsStop();
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::Run() {
            auto &PQClient = PQClientStart("worker");

            while (!sig_exiting) {

                Log()->Debug(APP_LOG_DEBUG_EVENT, _T("telegram bot cycle"));

                try {
                    PQClient.Wait();
                } catch (Delphi::Exception::Exception &E) {
                    Log()->Error(APP_LOG_ERR, 0, "%s", E.what());
                }

                if (sig_terminate || sig_quit) {
                    if (sig_quit) {
                        sig_quit = 0;
                        Log()->Debug(APP_LOG_DEBUG_EVENT, _T("gracefully shutting down"));
                        Application()->Header(_T("telegram bot is shutting down"));
                    }

                    if (!sig_exiting) {
                        sig_exiting = 1;
                    }
                }

                if (sig_reconfigure) {
                    sig_reconfigure = 0;
                    Log()->Debug(APP_LOG_DEBUG_EVENT, _T("reconfiguring"));

                    Reload();
                }

                if (sig_reopen) {
                    sig_reopen = 0;
                    Log()->Debug(APP_LOG_DEBUG_EVENT, _T("reopening logs"));
                }
            }

            Log()->Debug(APP_LOG_DEBUG_EVENT, _T("stop telegram bot"));
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::Reload() {
            CServerProcess::Reload();

            m_CheckDate = 0;
            m_CallDate = 0;

            m_Status = psStopped;

            Log()->Notice("[%s] Successful reloading", CONFIG_SECTION_NAME);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoFatal(const Delphi::Exception::Exception &E) {
            m_CheckDate = Now() + (CDateTime) SLEEP_SECOND_AFTER_ERROR / SecsPerDay; // 10 sec;
            m_CallDate = 0;

            m_Status = psStopped;

            Log()->Error(APP_LOG_ERR, 0, "%s", E.what());
            Log()->Notice("Continue after %d seconds", SLEEP_SECOND_AFTER_ERROR);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoError(const Delphi::Exception::Exception &E) {
            Log()->Error(APP_LOG_ERR, 0, "%s", E.what());
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::InitListen() {

            auto OnExecuted = [this](CPQPollQuery *APollQuery) {
                try {
                    auto pResult = APollQuery->Results(0);

                    if (pResult->ExecStatus() != PGRES_COMMAND_OK) {
                        throw Delphi::Exception::EDBError(pResult->GetErrorMessage());
                    }

                    APollQuery->Connection()->Listeners().Add(PG_LISTEN_NAME);
#if defined(_GLIBCXX_RELEASE) && (_GLIBCXX_RELEASE >= 9)
                    APollQuery->Connection()->OnNotify([this](auto && APollQuery, auto && ANotify) { DoPostgresNotify(APollQuery, ANotify); });
#else
                    APollQuery->Connection()->OnNotify(std::bind(&CPGFetch::DoPostgresNotify, this, _1, _2));
#endif
                    m_Status = Process::psRunning;
                } catch (Delphi::Exception::Exception &E) {
                    DoError(E);
                }
            };

            auto OnException = [](CPQPollQuery *APollQuery, const Delphi::Exception::Exception &E) {
                DoError(E);
            };

            CStringList SQL;

            SQL.Add("LISTEN " PG_LISTEN_NAME ";");

            try {
                ExecSQL(SQL, nullptr, OnExecuted, OnException);
            } catch (Delphi::Exception::Exception &E) {
                DoError(E);
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::CheckListen() {
            if (!GetPQClient().CheckListen(PG_LISTEN_NAME))
                InitListen();
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::UnloadQueue() {
            const auto index = m_Queue.IndexOf(this);
            if (index != -1) {
                const auto pQueue = m_Queue[index];
                for (int i = 0; i < pQueue->Count(); ++i) {
                    auto pHandler = (CBotHandler *) pQueue->Item(i);
                    if (pHandler != nullptr) {
                        pHandler->Handler();
                        if (m_Progress >= m_MaxQueue)
                            break;
                    }
                }
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::CheckTimeOut(CDateTime Now) {
            const auto index = m_Queue.IndexOf(this);
            if (index != -1) {
                const auto pQueue = m_Queue[index];
                for (int i = pQueue->Count() - 1; i >= 0; i--) {
                    auto pHandler = (CBotHandler *) pQueue->Item(i);
                    if (pHandler != nullptr) {
                        if ((pHandler->TimeOut() > 0) && (Now >= pHandler->TimeOut())) {
                            DoFail(pHandler, "Connection timed out");
                        }
                    }
                }
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DeleteHandler(CBotHandler *AHandler) {
            delete AHandler;
            if (m_Progress > 0)
                DecProgress();
            UnloadQueue();
        }
        //--------------------------------------------------------------------------------------------------------------

        int CTGBot::AddToQueue(CBotHandler *AHandler) {
            return m_Queue.AddToQueue(this, AHandler);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::InsertToQueue(int Index, CBotHandler *AHandler) {
            m_Queue.InsertToQueue(this, Index, AHandler);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::RemoveFromQueue(CBotHandler *AHandler) {
            m_Queue.RemoveFromQueue(this, AHandler);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoBot(CBotHandler *AHandler) {
            DeleteHandler(AHandler);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoFail(CBotHandler *AHandler, const CString &Message) {
            DeleteHandler(AHandler);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::CallHeartbeat() {

            CStringList SQL;

            SQL.Add("SELECT bot.heartbeat();");

            try {
                ExecSQL(SQL);
            } catch (Delphi::Exception::Exception &E) {
                DoFatal(E);
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::Heartbeat(CDateTime Now) {
            if (Now >= m_CheckDate) {
                m_CheckDate = Now + (CDateTime) 1 / MinsPerDay; // 1 min
                CheckListen();
            }

            UnloadQueue();
            CheckTimeOut(Now);

            if (m_Status == psRunning) {
                if ((Now >= m_CallDate)) {
                    m_CallDate = Now + (CDateTime) m_HeartbeatInterval / MSecsPerDay;
                    CallHeartbeat();
                }
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoTimer(CPollEventHandler *AHandler) {
            uint64_t exp;

            auto pTimer = dynamic_cast<CEPollTimer *> (AHandler->Binding());
            pTimer->Read(&exp, sizeof(uint64_t));

            try {
                Heartbeat(AHandler->TimeStamp());
            } catch (Delphi::Exception::Exception &E) {
                DoServerEventHandlerException(AHandler, E);
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        bool CTGBot::DoExecute(CTCPConnection *AConnection) {
            return true;
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoPostgresNotify(CPQConnection *AConnection, PGnotify *ANotify) {
            DebugNotify(AConnection, ANotify);

            if (CompareString(ANotify->relname, PG_LISTEN_NAME) == 0) {
#if defined(_GLIBCXX_RELEASE) && (_GLIBCXX_RELEASE >= 9)
                new CBotHandler(this, ANotify->extra, [this](auto &&Handler) { DoBot(Handler); });
#else
                new CBotHandler(this, ANotify->extra, std::bind(&CTGBot::DoBot, this, _1));
#endif
                UnloadQueue();
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoPostgresQueryExecuted(CPQPollQuery *APollQuery) {
            CPQResult *pResult;
            try {
                for (int i = 0; i < APollQuery->Count(); i++) {
                    pResult = APollQuery->Results(i);

                    if (pResult->ExecStatus() != PGRES_TUPLES_OK)
                        throw Delphi::Exception::EDBError(pResult->GetErrorMessage());
                }
            } catch (Delphi::Exception::Exception &E) {
                DoError(E);
            }
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoPostgresQueryException(CPQPollQuery *APollQuery, const Delphi::Exception::Exception &E) {
            DoError(E);
        }
        //--------------------------------------------------------------------------------------------------------------

        void CTGBot::DoPQConnectException(CPQConnection *AConnection, const Delphi::Exception::Exception &E) {
            CServerProcess::DoPQConnectException(AConnection, E);
            if (m_Status == psRunning) {
                DoFatal(E);
            }
        }
    }
}

}
