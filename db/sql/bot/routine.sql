--------------------------------------------------------------------------------
-- TELEGRAM BOT WEBHOOK --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.webhook (
  bot_id    uuid,
  body      jsonb
) RETURNS   void
AS $$
DECLARE
  r         record;
  vName     text;
BEGIN
  FOR r IN SELECT id, username FROM bot.list WHERE id = bot_id
  LOOP
    vName := concat(lower(r.username), '_webhook');
    PERFORM FROM pg_namespace n INNER JOIN pg_proc p ON n.oid = p.pronamespace WHERE n.nspname = 'bot' AND p.proname = vName;
    IF FOUND THEN
      EXECUTE format('SELECT bot.%s($1, $2);', vName) USING r.id, body;
    END IF;
  END LOOP;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- TELEGRAM BOT HEARTBEAT ------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.heartbeat (
) RETURNS   void
AS $$
DECLARE
  r         record;
  vName     text;
BEGIN
  FOR r IN SELECT id, username FROM bot.list
  LOOP
    vName := concat(lower(r.username), '_heartbeat');
    PERFORM FROM pg_namespace n INNER JOIN pg_proc p ON n.oid = p.pronamespace WHERE n.nspname = 'bot' AND p.proname = vName;
    IF FOUND THEN
      EXECUTE format('SELECT bot.%s($1);', vName) USING r.id;
    END IF;
  END LOOP;
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
