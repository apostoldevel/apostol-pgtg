--------------------------------------------------------------------------------
-- AddEventLog -----------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.AddEventLog (
  pType		char,
  pUsername text,
  pCode		integer,
  pEvent	text,
  pText		text,
  pCategory text DEFAULT null
) RETURNS	bigint
AS $$
DECLARE
  nId		bigint;
BEGIN
  INSERT INTO bot.log (type, username, code, event, text, category)
  VALUES (pType, pUsername, pCode, pEvent, pText, pCategory)
  RETURNING id INTO nId;
  RETURN nId;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- NewEventLog -----------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.NewEventLog (
  pType		char,
  pUsername text,
  pCode		integer,
  pEvent	text,
  pText		text,
  pCategory text DEFAULT null
) RETURNS	void
AS $$
DECLARE
  nId		bigint;
BEGIN
  nId := AddEventLog(pType, pUsername, pCode, pEvent, pText, pCategory);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- WriteToEventLog -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.WriteToEventLog (
  pType		char,
  pCode		integer,
  pText		text,
  pEvent	text DEFAULT null,
  pUsername text DEFAULT null
) RETURNS	void
AS $$
DECLARE
  vCategory text;
BEGIN
  pEvent := coalesce(pEvent, 'bot');
  pUsername := coalesce(pUsername, session_user);

  IF pType IN ('M', 'W', 'E', 'D') THEN
    PERFORM NewEventLog(pType, pUsername, pCode, pEvent, pText, vCategory);
  END IF;

  IF pType = 'D' THEN
    pType := 'N';
  END IF;

  IF pType = 'N' THEN
    RAISE NOTICE '[%] [%] [%] [%] %', pType, pUsername, pCode, pEvent, pText;
  END IF;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- DeleteEventLog --------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.DeleteEventLog (
  pId		bigint
) RETURNS	void
AS $$
BEGIN
  DELETE FROM bot.log WHERE id = pId;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION ParseMessage -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.ParseMessage (
  pMessage      text,
  OUT code      int,
  OUT message   text
) RETURNS       record
AS $$
BEGIN
  IF SubStr(pMessage, 1, 4) = 'ERR-' THEN
    code := SubStr(pMessage, 5, 5);
    message := SubStr(pMessage, 12);
  ELSE
    code := -1;
    message := pMessage;
  END IF;
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;

--------------------------------------------------------------------------------
-- WriteDiagnostics ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.WriteDiagnostics (
  pMessage      text,
  pContext      text default null
) RETURNS       void
AS $$
DECLARE
  ErrorCode     int;
  ErrorMessage  text;
BEGIN
  PERFORM SetErrorMessage(pMessage);

  SELECT * INTO ErrorCode, ErrorMessage FROM ParseMessage(pMessage);

  PERFORM WriteToEventLog('E', ErrorCode, ErrorMessage);

  IF pContext IS NOT NULL THEN
    PERFORM WriteToEventLog('D', ErrorCode, pContext);
  END IF;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION SetErrorMessage ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.SetErrorMessage (
  pMessage 	text
) RETURNS 	void
AS $$
BEGIN
  PERFORM SetVar('bot', 'error_message', pMessage);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION GetErrorMessage ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.GetErrorMessage (
) RETURNS 	text
AS $$
BEGIN
  RETURN GetVar('bot', 'error_message');
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;
