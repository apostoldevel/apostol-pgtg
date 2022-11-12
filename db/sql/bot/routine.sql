--------------------------------------------------------------------------------
-- TELEGRAM BOT WEBHOOK --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.webhook (
  bot_id    uuid,
  body      jsonb
) RETURNS   bool
AS $$
DECLARE
  b         record;
  r         record;
  m         record;
  c         record;
  f         record;

  message   text;
BEGIN
  SELECT * INTO b FROM bot.list WHERE id = bot_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT * INTO r FROM jsonb_to_record(body) AS x(message jsonb, update_id double precision);
  SELECT * INTO m FROM jsonb_to_record(r.message) AS x(chat jsonb, date double precision, "from" jsonb, text text, entities jsonb, update_id double precision);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id int, type text, username text, last_name text, full_name text);
  SELECT * INTO f FROM jsonb_to_record(m."from") AS x(id int, is_bot bool, username text, last_name text, full_name text, language_code text);

  CASE m.text
  WHEN '/start' THEN
    IF f.language_code = 'ru' THEN
      message := format('Здравствуйте! Меня зовут %s.', b.full_name);
    ELSE
      message := format('Hello! My name is %s.', b.full_name);
    END IF;
  WHEN '/help' THEN
    IF f.language_code = 'ru' THEN
      message := 'К сожалению, я пока не могу вам помочь.';
    ELSE
       message := 'Unfortunately, I can''t help you yet.';
    END IF;
  WHEN '/settings' THEN
    IF f.language_code = 'ru' THEN
      message := 'Не применимо.';
    ELSE
      message := 'Not applicable.';
    END IF;
  ELSE
    IF f.language_code = 'ru' THEN
      message := 'Неизвестная команда.';
    ELSE
      message := 'Unknown command.';
    END IF;
  END CASE;

  PERFORM tg.send_message(bot_id, c.id, message);

  RETURN true;
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
BEGIN
  FOR r IN SELECT id FROM bot.list
  LOOP

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
