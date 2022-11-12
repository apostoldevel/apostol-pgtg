/*++

Program name:

  tgpg

Module Name:

  TGBot.hpp

Notices:

  Process: Telegram bot

Author:

  Copyright (c) Prepodobny Alen

  mailto: alienufo@inbox.ru
  mailto: ufocomp@gmail.com

--*/

#ifndef APOSTOL_PROCESS_TELEGRAM_BOT_HPP
#define APOSTOL_PROCESS_TELEGRAM_BOT_HPP
//----------------------------------------------------------------------------------------------------------------------

extern "C++" {

namespace Apostol {

    namespace Processes {

        class CTGBot;
        class CBotHandler;
        //--------------------------------------------------------------------------------------------------------------

        typedef std::function<void (CBotHandler *Handler)> COnBotHandlerEvent;
        //--------------------------------------------------------------------------------------------------------------

        class CBotHandler: public CPollConnection {
        private:

            CTGBot *m_pModule;

            bool m_Allow;

            CJSON m_Payload;

            COnBotHandlerEvent m_Handler;

            int AddToQueue();
            void RemoveFromQueue();

        protected:

            void SetAllow(bool Value) { m_Allow = Value; }

        public:

            CBotHandler(CTGBot *AModule, const CString &Data, COnBotHandlerEvent && Handler);

            ~CBotHandler() override;

            const CJSON &Payload() const { return m_Payload; }

            bool Allow() const { return m_Allow; };
            void Allow(bool Value) { SetAllow(Value); };

            bool Handler();

            void Close() override;

        };

        //--------------------------------------------------------------------------------------------------------------

        //-- CTGBot ----------------------------------------------------------------------------------------------------

        //--------------------------------------------------------------------------------------------------------------

        class CTGBot: public CProcessCustom {
            typedef CProcessCustom inherited;

        private:

            CQueue m_Queue;
            CQueueManager m_QueueManager;

            CDateTime m_CheckDate;
            CDateTime m_CallDate;

            size_t m_Progress;
            size_t m_MaxQueue;

            CProcessStatus m_Status;

            int m_HeartbeatInterval;

            void InitListen();
            void CheckListen();

            void UnloadQueue();
            void CheckTimeOut(CDateTime Now);

            void DeleteHandler(CBotHandler *AHandler);

            void BeforeRun() override;
            void AfterRun() override;

            void CallHeartbeat();

            void Heartbeat(CDateTime Now);

        protected:

            void DoBot(CBotHandler *AHandler);
            void DoFail(CBotHandler *AHandler, const CString &Message);

            void DoTimer(CPollEventHandler *AHandler) override;

            void DoFatal(const Delphi::Exception::Exception &E);
            static void DoError(const Delphi::Exception::Exception &E);

            bool DoExecute(CTCPConnection *AConnection) override;

            void DoPostgresNotify(CPQConnection *AConnection, PGnotify *ANotify);

            void DoPostgresQueryExecuted(CPQPollQuery *APollQuery);
            void DoPostgresQueryException(CPQPollQuery *APollQuery, const Delphi::Exception::Exception &E);

            void DoPQConnectException(CPQConnection *AConnection, const Delphi::Exception::Exception &E) override;

        public:

            explicit CTGBot(CCustomProcess* AParent, CApplication *AApplication);

            ~CTGBot() override = default;

            static class CTGBot *CreateProcess(CCustomProcess *AParent, CApplication *AApplication) {
                return new CTGBot(AParent, AApplication);
            }

            void Run() override;
            void Reload() override;

            void IncProgress() { m_Progress++; }
            void DecProgress() { m_Progress--; }

            int AddToQueue(CBotHandler *AHandler);
            void InsertToQueue(int Index, CBotHandler *AHandler);
            void RemoveFromQueue(CBotHandler *AHandler);

            CQueue &Queue() { return m_Queue; }
            const CQueue &Queue() const { return m_Queue; }

            CPollManager *ptrQueueManager() { return &m_QueueManager; }

            CPollManager &QueueManager() { return m_QueueManager; }
            const CPollManager &QueueManager() const { return m_QueueManager; }

        };
        //--------------------------------------------------------------------------------------------------------------

    }
}

using namespace Apostol::Processes;
}
#endif //APOSTOL_PROCESS_TELEGRAM_BOT_HPP
