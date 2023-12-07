--------------------------------------------------------------------------------
-- WEBHOOK FUNCTION ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.BitcoinBalanceDetectorBot_webhook (
  pBotId    uuid,
  pBody     jsonb
) RETURNS   void
AS $$
DECLARE
  b         record;
BEGIN
  SELECT * INTO b FROM jsonb_to_record(pBody) AS x(message jsonb, callback_query jsonb, update_id bigint);

  IF b.message IS NOT NULL THEN
    PERFORM bot.bbd_parse_message(pBotId, b.message, b.update_id);
  END IF;

  IF b.callback_query IS NOT NULL THEN
    PERFORM bot.bbd_parse_callback_query(pBotId, b.callback_query, b.update_id);
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- HEARTBEAT FUNCTION ----------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.BitcoinBalanceDetectorBot_heartbeat (
  pBotId        uuid
) RETURNS       void
AS $$
DECLARE
  r             record;
  d             record;

  i             interval;

  address       text;

  vMessage      text;
  vContext      text;
BEGIN
  FOR d IN
    SELECT bot_id, chat_id, user_id
      FROM bot.data td INNER JOIN bot.list tl ON td.bot_id = tl.id AND tl.downtime < Now()
     WHERE bot_id = pBotId
     GROUP BY bot_id, chat_id, user_id
     ORDER BY bot_id, chat_id, user_id
  LOOP
    UPDATE bot.list SET downtime = Now() + INTERVAL '30 sec' WHERE id = d.bot_id;

    SELECT make_interval(secs => value::int) INTO i
      FROM bot.data
     WHERE bot_id = d.bot_id
       AND chat_id = d.chat_id
       AND user_id = d.user_id
       AND category = 'settings'
       AND key = 'interval';

    i := coalesce(i, INTERVAL '1 min');

    FOR r IN
      SELECT key
        FROM bot.data
       WHERE bot_id = d.bot_id
         AND chat_id = d.chat_id
         AND user_id = d.user_id
         AND category = 'address'
         AND updated + i <= Now()
       ORDER BY updated
       LIMIT 50
    LOOP
      UPDATE bot.data
         SET updated = Now()
       WHERE bot_id = d.bot_id
         AND chat_id = d.chat_id
         AND user_id = d.user_id
         AND category = 'address'
         AND key = r.key;

      address := coalesce(address || '|', '') || r.key;
    END LOOP;

    IF address IS NOT NULL THEN
      PERFORM http.fetch(format('https://blockchain.info/multiaddr?active=%s&n=0', address), 'GET', null, null, 'bot.bbd_blockchain_done', 'bot.bbd_blockchain_fail', 'blockchain', pBotId::text, 'multiaddr');
      EXIT WHEN true; -- one circle - one user
    END IF;
  END LOOP;
EXCEPTION
WHEN others THEN
  GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
  PERFORM WriteDiagnostics(vMessage, vContext);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- MESSAGE ---------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_parse_message (
  pBotId        uuid,
  pMessage      jsonb,
  pUpdateId     bigint
) RETURNS       void
AS $$
DECLARE
  b             record;
  m             record;
  c             record;
  u             record;
  f             record;

  isCommand     bool;

  keyboard      jsonb;

  vParam        text[];

  vCommand      text;
  vMessage      text;
  vDocument     text;
  vFileName     text;
BEGIN
  SELECT * INTO b FROM bot.list WHERE id = pBotId;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO m FROM jsonb_to_record(pMessage) AS x(chat jsonb, date double precision, "from" jsonb, caption text, text text, entities jsonb, document jsonb, message_id bigint);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id bigint, type text, username text, last_name text, first_name text);
  SELECT * INTO u FROM jsonb_to_record(m."from") AS x(id bigint, is_bot bool, username text, last_name text, first_name text, language_code text);
  SELECT * INTO f FROM jsonb_to_record(m.document) AS x(file_id text, file_name text, file_size int, mime_type text, file_unique_id text);

  IF m.document IS NOT NULL THEN
    IF f.mime_type = 'text/csv' THEN
      IF u.language_code = 'ru' THEN
        vMessage := format('Загрузка файла: "%s".', f.file_name);
      ELSE
        vMessage := format('Downloading file: "%s".', f.file_name);
      END IF;

      PERFORM bot.new_file(f.file_id, b.id, c.id, u.id, f.file_name, '/', f.file_size, Now(), null, f.file_unique_id, m.caption, f.mime_type);
      PERFORM tg.get_file(b.id, f.file_id, 'bot.get_file_done', 'bot.get_file_fail');
    ELSE
      IF u.language_code = 'ru' THEN
        vMessage := format('Неверный тип файла: %s', f.mime_type);
      ELSE
        vMessage := format('Invalid file type: %s', f.mime_type);
      END IF;
    END IF;
  END IF;

  IF m.text IS NOT NULL THEN
    PERFORM WriteToEventLog('M', 0, m.text, 'message', c.username, 'telegram');

    isCommand := SubStr(m.text, 1, 1) = '/';

    IF isCommand THEN
      vParam := string_to_array(m.text, ' ');
      vCommand := replace(vParam[1], '@' || b.username, '');
    ELSE
      SELECT command INTO vCommand FROM bot.context WHERE bot_id = b.id AND chat_id = c.id AND user_id = u.id;
    END IF;

    PERFORM bot.context(b.id, c.id, u.id, vCommand, m.text, pMessage, to_timestamp(m.date));

    CASE vCommand
    WHEN '/start' THEN
        IF u.language_code = 'ru' THEN
	    vMessage := format('Здравствуйте, Вас приветствует бот %s!', b.full_name);
      ELSE
	    vMessage := format('Hello, you are welcomed by a bot %s!', b.full_name);
      END IF;

      PERFORM bot.bbd_command_start(u.language_code, to_timestamp(m.date));
    WHEN '/help' THEN
      vMessage := bot.bbd_command_help(u.language_code);
    WHEN '/add' THEN
      IF isCommand THEN
        IF u.language_code = 'ru' THEN
          vMessage := 'Введите, пожалуйста, один или несколько Bitcoin адресов.';
        ELSE
          vMessage := 'Please enter one or more Bitcoin addresses.';
        END IF;

        IF array_length(vParam, 1) > 1 THEN
          vMessage := bot.bbd_command_add(vParam[2:], u.language_code, to_timestamp(m.date));
        END IF;
      ELSE
        vMessage := bot.bbd_command_add(string_to_array(replace(m.text, E'\n', ' '), ' '), u.language_code, to_timestamp(m.date));
      END IF;
    WHEN '/delete' THEN
      IF isCommand THEN
        IF u.language_code = 'ru' THEN
          vMessage := 'Введите, пожалуйста, один или несколько Bitcoin адресов.';
        ELSE
          vMessage := 'Please enter one or more Bitcoin addresses.';
        END IF;

        IF array_length(vParam, 1) > 1 THEN
          vMessage := bot.bbd_command_delete(vParam[2:], u.language_code);
        END IF;
      ELSE
        vMessage := bot.bbd_command_delete(string_to_array(replace(m.text, E'\n', ' '), ' '), u.language_code);
      END IF;
    WHEN '/list' THEN
      IF isCommand THEN
        vMessage := bot.bbd_command_list(u.language_code);
      END IF;
    WHEN '/check' THEN
      IF isCommand THEN
        vMessage := bot.bbd_command_check(u.language_code);
      END IF;
    WHEN '/settings' THEN
      IF isCommand THEN
        IF u.language_code = 'ru' THEN
          vMessage := E'Введите одно или несколько настроек в формате:\r\n<pre>ключ=значение</pre>';
          vMessage := concat(vMessage, E'\r\n\r\nТекущие настройки:\r\n\r\n');
        ELSE
          vMessage := 'Enter one or more settings in the format:\r\n<pre>key=value</pre>';
          vMessage := concat(vMessage, E'\r\n\r\nCurrent settings:\r\n\r\n');
        END IF;
        vMessage := concat(vMessage, bot.bbd_command_settings(null, u.language_code));
      ELSE
        vMessage := bot.bbd_command_settings(string_to_array(m.text, E'\n'), u.language_code);
      END IF;
    ELSE
      IF u.language_code = 'ru' THEN
        vMessage := 'Неизвестная команда.';
      ELSE
        vMessage := 'Unknown command.';
      END IF;
    END CASE;

  END IF;

  IF vMessage IS NOT NULL THEN
    PERFORM tg.send_message(b.id, c.id, vMessage, 'HTML', keyboard, 'telegram_message_done');
  END IF;

  IF vFileName IS NOT NULL AND vDocument IS NOT NULL THEN
    PERFORM tg.send_document_multipart(b.id, c.id, vFileName, vDocument, 'text/csv');
  ELSE
    IF vDocument IS NOT NULL THEN
      PERFORM tg.send_document(b.id, c.id, vDocument, 'HTML', keyboard);
    END IF;
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- CALLBACK QUERY --------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_parse_callback_query (
  pBotId        uuid,
  pQuery        jsonb,
  pUpdateId     bigint
) RETURNS       void
AS $$
DECLARE
  b             record;
  q             record;
  u             record;
  m             record;
  c             record;

  showAlert     bool DEFAULT false;
  editMessage   bool DEFAULT false;

  vParams       text[];
  vText         text;
  vData         text;

  vMessage      text;
  vDocument     text;
  vFileName     text;
  vContentType  text;

  keyboard      jsonb;
BEGIN
  SELECT * INTO b FROM bot.list WHERE id = pBotId;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO q FROM jsonb_to_record(pQuery) AS x(id text, data text, "from" jsonb, message jsonb, chat_instance text);
  SELECT * INTO u FROM jsonb_to_record(q."from") AS x(id bigint, is_bot bool, username text, last_name text, first_name text, language_code text);
  SELECT * INTO m FROM jsonb_to_record(q.message) AS x(chat jsonb, date double precision, "from" jsonb, text text, entities jsonb, message_id bigint, reply_markup jsonb);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id bigint, type text, username text, last_name text, first_name text);

  IF u.language_code = 'ru' THEN
	vText := 'Что-то пошло не так :(';
  ELSE
	vText := 'Something went wrong :(';
  END IF;

  vParams := string_to_array(q.data, '#');
  vData := vParams[1];

  CASE vData
  WHEN 'delete_message' THEN

	vText := '';
    vMessage = null;

    PERFORM tg.delete_message(b.id, c.id, m.message_id);

  ELSE

    IF u.language_code = 'ru' THEN
      vMessage := 'Неизвестные данные.';
    ELSE
      vMessage := 'Unknown data.';
    END IF;

  END CASE;

  PERFORM tg.answer_callback_query(b.id, q.id, vText, showAlert);

  PERFORM WriteToEventLog('M', 0, coalesce(NULLIF(vText, ''), m.text), q.data, u.username, 'telegram');

  IF vMessage IS NOT NULL THEN
    IF editMessage THEN
      PERFORM tg.edit_message_text(b.id, c.id, m.message_id, vMessage, 'HTML', keyboard);
	ELSE
      PERFORM tg.send_message(b.id, c.id, vMessage, 'HTML', keyboard, 'telegram_message_done');
    END IF;
  END IF;

  IF vFileName IS NOT NULL AND vDocument IS NOT NULL THEN
    PERFORM tg.send_document_multipart(b.id, c.id, vFileName, vDocument, vContentType);
  ELSE
    IF vDocument IS NOT NULL THEN
      PERFORM tg.send_document(b.id, c.id, vDocument, 'HTML');
    END IF;
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.bbd_blockchain_done -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_blockchain_done (
  pRequest  uuid
) RETURNS   void
AS $$
DECLARE
  r             record;
  e             record;
  d             record;

  reply         jsonb;

  vLanguageCode text;

  vOld          text;
  vNew          text;

  vMessage      text;
  vContext      text;
BEGIN
  SELECT agent, command, resource, status, status_text, response INTO r FROM http.fetch WHERE id = pRequest;

  IF coalesce(r.status, 0) = 200 THEN

    reply := r.response::jsonb;

    IF r.agent = 'blockchain' AND r.command = 'multiaddr' THEN

      FOR e IN SELECT * FROM jsonb_to_recordset(reply->'addresses') AS x(address text, n_tx int, total_received double precision, total_sent double precision, final_balance double precision)
      LOOP
        vNew := format(E'%s\t%s\t%s\t%s', e.n_tx, to_char(e.total_received / 100000000, 'FM999999990.00000000'), to_char(e.total_sent / 100000000, 'FM999999990.00000000'), to_char(e.final_balance / 100000000, 'FM999999990.00000000'));

        FOR d IN SELECT bot_id, chat_id, user_id FROM bot.data WHERE category = 'address' AND key = e.address GROUP BY bot_id, chat_id, user_id
        LOOP
          SELECT language_code INTO vLanguageCode FROM bot.list WHERE id = d.bot_id;

          IF vLanguageCode = 'ru' THEN
            vMessage := E'Обнаружено изменение баланса:';
          ELSE
            vMessage := E'Balance Change Detected:';
          END IF;

          SELECT value INTO vOld
            FROM bot.data
           WHERE bot_id = d.bot_id
             AND chat_id = d.chat_id
             AND user_id = d.user_id
             AND category = 'address'
             AND key = e.address;

          PERFORM bot.set_data('address', e.address, vNew, row_to_json(e)::jsonb, Now(), d.user_id, d.chat_id, d.bot_id);

          IF encode(digest(vOld, 'md5'), 'hex') != encode(digest(vNew, 'md5'), 'hex') THEN
            IF vOld = 'Not data' THEN
              vMessage := concat(vMessage, E'\r\n\r\n<pre>', e.address, E'\r\n', vNew, '</pre>');
			ELSE
              vMessage := concat(vMessage, E'\r\n\r\n<pre>', e.address, E'\r\n', vOld, E'\r\n', vNew, '</pre>');
			END IF;

            PERFORM tg.send_message(d.bot_id, d.user_id, vMessage, 'HTML');
          END IF;
        END LOOP;
      END LOOP;

      DELETE FROM http.response WHERE request = pRequest;
      DELETE FROM http.request WHERE id = pRequest;
    END IF;

  ELSIF coalesce(r.status, 500) = 500 THEN

    UPDATE bot.list SET downtime = Now() + INTERVAL '1 hour';
    PERFORM WriteToEventLog('E', r.status, coalesce(r.response, r.status_text), r.agent);

  ELSE

    UPDATE bot.list SET downtime = Now() + INTERVAL '5 min';
    PERFORM WriteToEventLog('E', r.status, coalesce(r.response, r.status_text), r.agent);

  END IF;
EXCEPTION
WHEN others THEN
  GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
  PERFORM WriteDiagnostics(vMessage, vContext);

  UPDATE bot.list SET downtime = Now() + INTERVAL '10 min';
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- bot.bbd_blockchain_fail -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_blockchain_fail (
  pRequest  uuid
) RETURNS   void
AS $$
DECLARE
  r         record;
BEGIN
  SELECT method, resource, agent, error INTO r
    FROM http.request
   WHERE id = pRequest;

  UPDATE bot.list SET downtime = Now() + INTERVAL '60 sec';

  PERFORM WriteToEventLog('E', 0, r.error, r.agent);
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- bot.bbd_get_file_done -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_get_file_done (
  pRequest      uuid
) RETURNS       void
AS $$
DECLARE
  r             record;
  f             record;
  e             record;
  b             record;

  count         int;

  uBotId        uuid;
  vFileId       text;

  reply         jsonb;

  vLanguageCode text;
  vMessage      text;
  vContext      text;
BEGIN
  SELECT agent, profile, command, resource, status, status_text, response, message INTO r FROM http.fetch WHERE id = pRequest;

  uBotId := r.profile::uuid;
  SELECT language_code INTO vLanguageCode FROM bot.list WHERE id = uBotId;

  IF coalesce(r.status, 0) = 200 THEN

    IF r.agent = 'telegram' AND r.command = 'getFile' THEN

      reply := r.response::jsonb;

      SELECT * INTO f FROM jsonb_to_record(reply) AS x(ok bool, result jsonb);

      IF NOT f.ok THEN
		RETURN;
	  END IF;

      FOR e IN SELECT * FROM jsonb_to_record(f.result) AS x(file_id text, file_unique_id text, file_size int, file_path text)
      LOOP
        PERFORM bot.update_file(e.file_id, psize => e.file_size, plink => e.file_path);
        PERFORM tg.file_path(uBotId, e.file_id, e.file_path, 'bot.bbd_get_file_done', 'bot.bbd_get_file_fail');
      END LOOP;

    ELSIF r.agent = 'telegram' AND r.command = 'file_path' THEN

      vFileId := r.message;
      PERFORM bot.update_file(vFileId, pdata => convert_to(r.response, 'UTF-8'));

      SELECT bot_id, chat_id, user_id INTO b FROM bot.file WHERE file_id = vFileId;
      PERFORM bot.context(uBotId, b.chat_id, b.user_id, '/parse', null, null, Now());

      BEGIN
        count := bot.bbd_parse_file(vFileId);

        IF vLanguageCode = 'ru' THEN
          vMessage := format('Обработано <b>%s</b> строк.', count);
	    ELSE
          vMessage := format('Processed <b>%s</b> rows.', count);
	    END IF;
      EXCEPTION
      WHEN others THEN
        GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
        PERFORM WriteDiagnostics(vMessage, vContext);
      END;

      PERFORM tg.send_message(b.bot_id, b.chat_id, vMessage, 'HTML');
    END IF;

  ELSE

    PERFORM WriteToEventLog('E', r.status, coalesce(r.response, r.status_text), r.agent);

  END IF;
EXCEPTION
WHEN others THEN
  GET STACKED DIAGNOSTICS vMessage = MESSAGE_TEXT, vContext = PG_EXCEPTION_CONTEXT;
  PERFORM WriteDiagnostics(vMessage, vContext);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- bot.bbd_get_file_fail -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_get_file_fail (
  pRequest  uuid
) RETURNS   void
AS $$
DECLARE
  r         record;
BEGIN
  SELECT method, resource, agent, error INTO r
    FROM http.request
   WHERE id = pRequest;

  PERFORM WriteToEventLog('E', -1, r.error, r.agent);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- BITCOIN FUNCTION ------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FUNCTION IsLegacyAddress ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.IsLegacyAddress (
  pAddress  text
) RETURNS   bool
AS $$
DECLARE
  ch        char;
BEGIN
  IF NULLIF(pAddress, '') IS NOT NULL THEN
    ch := SubStr(pAddress, 1, 1);
    RETURN (ch = '1' OR ch = '2' OR ch = '3' OR ch = 'm' OR ch = 'n') AND (length(pAddress) >= 26 AND length(pAddress) <= 35);
  END IF;

  RETURN false;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION IsSegWitAddress ----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.IsSegWitAddress (
  pAddress  text
) RETURNS   bool
AS $$
DECLARE
  hrp       text;
BEGIN
  IF NULLIF(pAddress, '') IS NOT NULL THEN
    hrp := SubStr(pAddress, 1, 3);
    RETURN (hrp = 'bc1' OR hrp = 'tb1') AND (length(pAddress) = 42 OR length(pAddress) = 62);
  END IF;

  RETURN false;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION IsBitcoinAddress ---------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.IsBitcoinAddress (
  pAddress  text
) RETURNS   bool
AS $$
BEGIN
  RETURN IsLegacyAddress(pAddress) OR IsSegWitAddress(pAddress);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_start ------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_start (
  pLanguage text DEFAULT null,
  pUpdated  timestamptz DEFAULT null
) RETURNS   void
AS $$
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  pUpdated := coalesce(pUpdated, Now());

  IF pLanguage = 'ru' THEN
	PERFORM bot.set_data('help', '/help', 'Помощь', null, pUpdated);
	PERFORM bot.set_data('help', '/add', 'Добавить Bitcoin адрес', null, pUpdated);
	PERFORM bot.set_data('help', '/delete', 'Удалить Bitcoin адрес', null, pUpdated);
	PERFORM bot.set_data('help', '/list', 'Список адресов', null, pUpdated);
	PERFORM bot.set_data('help', '/check', 'Проверить баланс сейчас', null, pUpdated);
	PERFORM bot.set_data('help', '/settings', 'Настройки', null, pUpdated);
  ELSE
	PERFORM bot.set_data('help', '/help', 'Help', null, pUpdated);
	PERFORM bot.set_data('help', '/add', 'Add Bitcoin address', null, pUpdated);
	PERFORM bot.set_data('help', '/delete', 'Delete Bitcoin address', null, pUpdated);
	PERFORM bot.set_data('help', '/list', 'List addresses', null, pUpdated);
	PERFORM bot.set_data('help', '/check', 'Check balance now', null, pUpdated);
	PERFORM bot.set_data('help', '/settings', 'Settings', null, pUpdated);
  END IF;

  PERFORM bot.set_data('settings', 'interval', '60', jsonb_build_object('interval', 60), pUpdated);
  PERFORM bot.set_data('settings', 'encoding', 'UTF-8', jsonb_build_object('encoding', 'UTF-8'), pUpdated);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_help -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_help (
  pLanguage text DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  count     int;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');

  SELECT count(key) INTO count FROM get_data('help');
  IF count = 0 THEN
    PERFORM bot.command_start(pLanguage);
  END IF;

  FOR r IN SELECT * FROM get_data('help')
  LOOP
    vMessage := concat(coalesce(vMessage || E'\n', ''), concat('<code>', r.key, '</code>'), ' - ', r.value);
    count := count + 1;
  END LOOP;

  IF count = 0 THEN
    IF pLanguage = 'ru' THEN
      vMessage := 'Извините, я не могу помочь.';
    ELSE
      vMessage := 'Sorry I can''t help.';
    END IF;
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_add --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_add (
  pAddress  text[],
  pLanguage text DEFAULT null,
  pUpdated  timestamptz DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');

  FOR r IN SELECT unnest(pAddress) AS address
  LOOP
    IF IsBitcoinAddress(r.address) THEN
      PERFORM bot.set_data('address', r.address, 'Not data', null, coalesce(pUpdated, Now()));

      vMessage := concat(coalesce(vMessage || E'\r\n', ''), '<code>[+] ', r.address, '</code>');
    ELSE
      vMessage := concat(coalesce(vMessage || E'\r\n', ''), '<code>[!] ', r.address, '</code>');
    END IF;
  END LOOP;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_delete -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_delete (
  pAddress  text[],
  pLanguage text DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');

  FOR r IN SELECT unnest(pAddress) AS address
  LOOP
    IF IsBitcoinAddress(r.address) THEN
      IF bot.delete_data('address', r.address) THEN
        vMessage := concat(coalesce(vMessage || E'\r\n', ''), '<code>[-] ', r.address, '</code>');
      ELSE
        vMessage := concat(coalesce(vMessage || E'\r\n', ''), '<code>[?] ', r.address, '</code>');
      END IF;
    ELSE
      vMessage := concat(coalesce(vMessage || E'\r\n', ''), '<code>[!] ', r.address, '</code>');
    END IF;
  END LOOP;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_list -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_list (
  pLanguage text DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  count     int;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  count := 0;

  FOR r IN SELECT * FROM get_data('address')
  LOOP
    vMessage := concat(coalesce(vMessage || E'\r\n\r\n', '<pre>'), r.key, E'\r\n', r.value);
    count := count + 1;
  END LOOP;

  IF count = 0 THEN
    IF pLanguage = 'ru' THEN
      vMessage := 'Не найдено.';
    ELSE
      vMessage := 'Not found.';
    END IF;
  ELSE
    vMessage := vMessage || '</pre>';
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_check ------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_check (
  pLanguage text DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  i         interval;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  SELECT make_interval(secs => max(value::int)) INTO i FROM bot.data WHERE category = 'settings' AND key = 'interval';

  FOR r IN SELECT * FROM get_data('address')
  LOOP
    UPDATE bot.data
       SET updated = Now() - i
     WHERE category = 'address'
       AND bot_id = current_bot_id()
       AND chat_id = current_chat_id()
       and user_id = current_user_id();

    IF pLanguage = 'ru' THEN
      vMessage := 'Принято.';
    ELSE
      vMessage := 'Accepted.';
    END IF;
  END LOOP;

  IF vMessage IS NULL THEN
    IF pLanguage = 'ru' THEN
      vMessage := 'Не найдено.';
    ELSE
      vMessage := 'Not found.';
    END IF;
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bbd_command_settings -----------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_command_settings (
  pSettings text[] DEFAULT null,
  pLanguage text DEFAULT null,
  pUpdated  timestamptz DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  nValue    int;
  vData     text[];
  count     int;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  count := 0;

  IF pSettings IS NULL THEN

    FOR r IN SELECT * FROM get_data('settings')
    LOOP
      vMessage := concat(coalesce(vMessage || E'\r\n', '<pre>'), r.key, '=', r.value);
      count := count + 1;
    END LOOP;

  ELSE

    FOR r IN SELECT unnest(pSettings) AS settings
    LOOP
      vData := string_to_array(r.settings, '=');

      IF array_length(vData, 1) = 2 THEN
        IF vData[1] = ANY (ARRAY['interval']) THEN

          IF vData[1] = 'interval' THEN
            nValue := vData[2]::int;

            IF nValue < 60 THEN
			  nValue := 60;
			END IF;

            PERFORM bot.set_data('settings', vData[1], nValue::text, jsonb_build_object(vData[1], nValue), coalesce(pUpdated, Now()));
          END IF;

          vMessage := concat(coalesce(vMessage || E'\r\n', '<pre>'), '[+] ', vData[1], E'=', vData[2]);
        ELSE
          vMessage := concat(coalesce(vMessage || E'\r\n', '<pre>'), '[!] ', vData[1]);
        END IF;
      ELSE
        vMessage := concat(coalesce(vMessage || E'\r\n', '<pre>'), '[?] ', r.settings);
      END IF;

      count := count + 1;
    END LOOP;

  END IF;

  IF count > 0 THEN
    vMessage := vMessage || '</pre>';
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION bbd_parse_file -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.bbd_parse_file (
  pFileId       text
) RETURNS       int
AS $$
DECLARE
  f             record;
  r             record;
  c             record;

  arValues      text[];

  encoding      text;
  count         int DEFAULT 0;
BEGIN
  SELECT value INTO encoding FROM bot.get_data('settings', 'encoding');

  arValues := array_cat(null, ARRAY['#', 'address', 'count', 'received', 'sent', 'balance', 'description']);

  FOR f IN SELECT convert_from(file_data, 'UTF-8') AS data FROM bot.file WHERE file_id = pFileId
  LOOP
    FOR r IN SELECT * FROM string_to_table(f.data, E'\n') AS line
    LOOP
      FOR c IN SELECT * FROM string_to_table(r.line, E';') AS data
      LOOP
        IF count = 0 THEN
          IF NOT c.data = ANY (arValues) THEN
            RAISE EXCEPTION 'Invalid value "%" in header. Valid values: [%]', c.data, arValues;
          END IF;
        ELSE

		END IF;
      END LOOP;

      count := count + 1;
    END LOOP;
  END LOOP;

  RETURN count;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, public, pg_temp;
