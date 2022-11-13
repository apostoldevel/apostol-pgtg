--------------------------------------------------------------------------------
-- WEBHOOK FUNCTION ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.MyTelegramBot_webhook (
  bot_id    uuid,
  body      jsonb
) RETURNS   void
AS $$
DECLARE
  r         record;
  b         record;
  m         record;
  c         record;
  f         record;

  message   text;
BEGIN
  SELECT * INTO r FROM bot.list WHERE id = bot_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO b FROM jsonb_to_record(body) AS x(message jsonb, update_id double precision);
  SELECT * INTO m FROM jsonb_to_record(b.message) AS x(chat jsonb, date double precision, "from" jsonb, text text, entities jsonb, update_id double precision);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id int, type text, username text, last_name text, first_name text);
  SELECT * INTO f FROM jsonb_to_record(m."from") AS x(id int, is_bot bool, username text, last_name text, first_name text, language_code text);

  CASE m.text
  WHEN '/start' THEN
    message := format('Hello! My name is %s.', r.full_name);
  WHEN '/help' THEN
    message := 'Unfortunately, I can''t help you yet.';
  WHEN '/settings' THEN
    message := 'Not applicable.';
  ELSE
    message := 'Unknown command.';
  END CASE;

  PERFORM tg.send_message(r.id, c.id, message);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- HEARTBEAT FUNCTION ----------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.MyTelegramBot_heartbeat (
  bot_id    uuid
) RETURNS   void
AS $$
DECLARE
  r         record;
BEGIN
  SELECT * INTO r FROM bot.list WHERE id = bot_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Some code
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;