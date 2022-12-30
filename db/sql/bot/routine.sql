--------------------------------------------------------------------------------
-- FUNCTION SetVar -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	text
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), pValue, false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	numeric
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), to_char(pValue, 'FM999999999990'), false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	uuid
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), pValue::text, false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	timestamp
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), to_char(pValue, 'DD.MM.YYYY HH24:MI:SS'), false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	timestamptz
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), to_char(pValue, 'DD.MM.YYYY HH24:MI:SS'), false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetVar (
  pType		text,
  pName		text,
  pValue	date
) RETURNS	void
AS $$
BEGIN
  PERFORM set_config(concat(pType, '.', pName), to_char(pValue, 'DD.MM.YYYY HH24:MI:SS'), false);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION GetVar -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.GetVar (
  pType		text,
  pName 	text
) RETURNS   text
AS $$
BEGIN
  RETURN NULLIF(current_setting(concat(pType, '.', pName)), '');
EXCEPTION
WHEN syntax_error_or_access_rule_violation THEN
  RETURN null;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION current_bot_id -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.current_bot_id()
RETURNS		uuid
AS $$
BEGIN
  RETURN GetVar('context', 'bot_id')::uuid;
END
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION current_chat_id ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.current_chat_id()
RETURNS		bigint
AS $$
BEGIN
  RETURN GetVar('context', 'chat_id')::bigint;
END
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION current_user_id ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.current_user_id()
RETURNS		bigint
AS $$
BEGIN
  RETURN GetVar('context', 'user_id')::bigint;
END
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION current_command ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.current_command()
RETURNS		text
AS $$
BEGIN
  RETURN GetVar('context', 'command');
END
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- TELEGRAM BOT WEBHOOK --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.webhook (
  bot_id        uuid,
  body          jsonb
) RETURNS       void
AS $$
DECLARE
  r             record;

  vName         text;
  vMessage      text;
  vContext      text;
BEGIN
  FOR r IN SELECT id, username FROM bot.list WHERE id = bot_id
  LOOP
    vName := concat(lower(r.username), '_webhook');
    PERFORM FROM pg_namespace n INNER JOIN pg_proc p ON n.oid = p.pronamespace WHERE n.nspname = 'bot' AND p.proname = vName;
    IF FOUND THEN
      EXECUTE format('SELECT bot.%s($1, $2);', vName) USING r.id, body;
    END IF;
  END LOOP;
EXCEPTION
WHEN others THEN
  GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
  PERFORM WriteDiagnostics(vMessage, vContext);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- TELEGRAM BOT HEARTBEAT ------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.heartbeat (
) RETURNS       void
AS $$
DECLARE
  r             record;

  vName         text;
  vMessage      text;
  vContext      text;
BEGIN
  FOR r IN SELECT id, username FROM bot.list
  LOOP
    vName := concat(lower(r.username), '_heartbeat');
    PERFORM FROM pg_namespace n INNER JOIN pg_proc p ON n.oid = p.pronamespace WHERE n.nspname = 'bot' AND p.proname = vName;
    IF FOUND THEN
      EXECUTE format('SELECT bot.%s($1);', vName) USING r.id;
    END IF;
  END LOOP;
EXCEPTION
WHEN others THEN
  GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
  PERFORM WriteDiagnostics(vMessage, vContext);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.add ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.add (
  pId           uuid,
  pToken        text,
  pUsername     text,
  pFullName     text,
  pSecret       text DEFAULT null,
  pLanguageCode text DEFAULT null
) RETURNS       uuid
AS $$
BEGIN
  INSERT INTO bot.list (id, token, username, full_name, secret, language_code)
  VALUES (pId, pToken, pUsername, pFullName, pSecret, coalesce(pLanguageCode, 'en'))
  RETURNING id INTO pId;

  RETURN pId;
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.update ---------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.update (
  pId           uuid,
  pToken        text DEFAULT NULL,
  pUsername     text DEFAULT NULL,
  pFullName     text DEFAULT NULL,
  pSecret       text DEFAULT NULL,
  pLanguageCode text DEFAULT NULL
) RETURNS       bool
AS $$
BEGIN
  UPDATE bot.list
     SET token = coalesce(pToken, token),
         username = coalesce(pUsername, username),
         full_name = coalesce(pFullName, full_name),
         secret = coalesce(pSecret, secret),
         language_code = coalesce(pLanguageCode, language_code)
   WHERE id = pId;

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.set ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.set (
  pId           uuid,
  pToken        text DEFAULT NULL,
  pUsername     text DEFAULT NULL,
  pFullName     text DEFAULT NULL,
  pSecret       text DEFAULT NULL,
  pLanguageCode text DEFAULT NULL
) RETURNS       uuid
AS $$
BEGIN
  IF pId IS NOT NULL THEN
    PERFORM bot.update(pId, pToken, pUsername, pFullName, pSecret, pLanguageCode);
  ELSE
    pId := bot.add(pId, pToken, pUsername, pFullName, pSecret, pLanguageCode);
  END IF;

  RETURN pId;
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.context --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.context (
  pBotId        uuid,
  pChatId       bigint,
  pUserId       bigint,
  pCommand      text,
  pText         text,
  pData         jsonb,
  pUpdated      timestamptz
) RETURNS       void
AS $$
BEGIN
  INSERT INTO bot.context (bot_id, chat_id, user_id, command, text, data, updated)
  VALUES (pBotId, pChatId, pUserId, pCommand, pText, pData, coalesce(pUpdated, Now()))
  ON CONFLICT (bot_id, chat_id, user_id)
  DO UPDATE SET command = pCommand, text = pText, data = pData, updated = coalesce(pUpdated, Now());

  PERFORM SetVar('context', 'bot_id', pBotId);
  PERFORM SetVar('context', 'chat_id', pChatId);
  PERFORM SetVar('context', 'user_id', pUserId);
  PERFORM SetVar('context', 'command', pCommand);
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.data -----------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.data (
  pBotId        uuid,
  pChatId       bigint,
  pUserId       bigint,
  pCategory     text,
  pKey          text,
  pValue        text,
  pData         jsonb,
  pUpdated      timestamptz
) RETURNS       void
AS $$
BEGIN
  INSERT INTO bot.data (bot_id, chat_id, user_id, category, key, value, data, updated)
  VALUES (pBotId, pChatId, pUserId, pCategory, pKey, pValue, pData, coalesce(pUpdated, Now()))
  ON CONFLICT (bot_id, chat_id, user_id, category, key)
  DO UPDATE SET value = pValue, data = pData, updated = coalesce(pUpdated, Now());
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.set_data -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.set_data (
  pCategory     text,
  pKey          text,
  pValue        text,
  pData         jsonb DEFAULT null,
  pUpdated      timestamptz DEFAULT null,
  pUserId       bigint DEFAULT bot.current_user_id(),
  pChatId       bigint DEFAULT bot.current_chat_id(),
  pBotId        uuid DEFAULT bot.current_bot_id()
) RETURNS       void
AS $$
BEGIN
  PERFORM bot.data(pBotId, pChatId, pUserId, pCategory, pKey, pValue, pData, pUpdated);
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.get_data -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.get_data (
  pCategory     text,
  pKey          text DEFAULT null,
  pUserId       bigint DEFAULT bot.current_user_id(),
  pChatId       bigint DEFAULT bot.current_chat_id(),
  pBotId        uuid DEFAULT bot.current_bot_id(),
  OUT key       text,
  OUT value     text,
  OUT data      jsonb,
  OUT updated   timestamptz
) RETURNS       SETOF record
AS $$
BEGIN
  RETURN QUERY
    SELECT d.key, d.value, d.data, d.updated
      FROM bot.data d
     WHERE d.bot_id = pBotId
       AND d.chat_id = pChatId
       AND d.user_id = pUserId
       AND d.category = pCategory
       AND d.key = coalesce(pKey, d.key);
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bot.delete_data ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.delete_data (
  pCategory     text,
  pKey          text DEFAULT null,
  pUserId       bigint DEFAULT bot.current_user_id(),
  pChatId       bigint DEFAULT bot.current_chat_id(),
  pBotId        uuid DEFAULT bot.current_bot_id()
) RETURNS       bool
AS $$
BEGIN
  DELETE FROM bot.data d
     WHERE d.bot_id = pBotId
       AND d.chat_id = pChatId
       AND d.user_id = pUserId
       AND d.category = pCategory
       AND d.key = coalesce(pKey, d.key);

  RETURN FOUND;
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;
