--------------------------------------------------------------------------------
-- WEBHOOK FUNCTION ------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.BitcoinBalanceDetectorBot_webhook (
  pBotId    uuid,
  pBody     jsonb
) RETURNS   void
AS $$
DECLARE
  r         record;
  b         record;
  m         record;
  c         record;
  f         record;

  isCommand bool;

  vParam    text[];

  vCommand  text;
  vMessage  text;
BEGIN
  SELECT * INTO r FROM bot.list WHERE id = pBotId;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO b FROM jsonb_to_record(pBody) AS x(message jsonb, update_id double precision);
  SELECT * INTO m FROM jsonb_to_record(b.message) AS x(chat jsonb, date double precision, "from" jsonb, text text, entities jsonb, update_id double precision);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id int, type text, username text, last_name text, first_name text);
  SELECT * INTO f FROM jsonb_to_record(m."from") AS x(id int, is_bot bool, username text, last_name text, first_name text, language_code text);

  isCommand := SubStr(m.text, 1, 1) = '/';

  IF isCommand THEN
    vParam := string_to_array(m.text, ' ');
    vCommand := vParam[1];
  ELSE
    SELECT command INTO vCommand FROM bot.context WHERE pBotId = pBotId AND chat_id = c.id AND user_id = f.id;
  END IF;

  PERFORM bot.context(r.id, c.id, f.id, vCommand, m.text, b.message, to_timestamp(b.update_id));

  CASE vCommand
  WHEN '/start' THEN
    IF f.language_code = 'ru' THEN
      vMessage := format('Здравствуйте, Вас приветствует бот %s!', r.full_name);
    ELSE
      vMessage := format('Hello, you are welcomed by a bot %s!', r.full_name);
    END IF;

    IF f.language_code = 'ru' THEN
      PERFORM bot.set_data('help', '/help', 'Помощь', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/add', 'Добавить Bitcoin адрес', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/delete', 'Удалить Bitcoin адрес', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/list', 'Список адресов', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/check', 'Проверить баланс сейчас', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/settings', 'Настройки', null, to_timestamp(b.update_id));
    ELSE
      PERFORM bot.set_data('help', '/help', 'Help', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/add', 'Add Bitcoin address', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/delete', 'Delete Bitcoin address', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/list', 'List addresses', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/check', 'Check balance now', null, to_timestamp(b.update_id));
      PERFORM bot.set_data('help', '/settings', 'Settings', null, to_timestamp(b.update_id));
    END IF;

    PERFORM bot.set_data('settings', 'interval', '60', jsonb_build_object('interval', 60), to_timestamp(b.update_id));
  WHEN '/help' THEN
    vMessage := bot.command_help(f.language_code);
  WHEN '/add' THEN
    IF isCommand THEN
      IF f.language_code = 'ru' THEN
        vMessage := 'Введите, пожалуйста, один или несколько Bitcoin адресов.';
      ELSE
        vMessage := 'Please enter one or more Bitcoin addresses.';
      END IF;

      IF array_length(vParam, 1) > 1 THEN
        vMessage := bot.command_add(vParam[2:], f.language_code, to_timestamp(b.update_id));
      END IF;
    ELSE
      vMessage := bot.command_add(string_to_array(replace(m.text, E'\n', ' '), ' '), f.language_code, to_timestamp(b.update_id));
    END IF;
  WHEN '/delete' THEN
    IF isCommand THEN
      IF f.language_code = 'ru' THEN
        vMessage := 'Введите, пожалуйста, один или несколько Bitcoin адресов.';
      ELSE
        vMessage := 'Please enter one or more Bitcoin addresses.';
      END IF;

      IF array_length(vParam, 1) > 1 THEN
        vMessage := bot.command_delete(vParam[2:], f.language_code);
      END IF;
    ELSE
      vMessage := bot.command_delete(string_to_array(replace(m.text, E'\n', ' '), ' '), f.language_code);
    END IF;
  WHEN '/list' THEN
    IF isCommand THEN
      vMessage := bot.command_list(f.language_code);
    END IF;
  WHEN '/check' THEN
    IF isCommand THEN
      vMessage := bot.command_check(f.language_code);
    END IF;
  WHEN '/settings' THEN
    IF isCommand THEN
      IF f.language_code = 'ru' THEN
        vMessage := E'Введите одно или несколько настроек в формате:\r\n<pre>ключ=значение</pre>';
        vMessage := concat(vMessage, E'\r\n\r\nТекущие настройки:\r\n\r\n');
      ELSE
        vMessage := 'Enter one or more settings in the format:\r\n<pre>key=value</pre>';
        vMessage := concat(vMessage, E'\r\n\r\nCurrent settings:\r\n\r\n');
      END IF;
      vMessage := concat(vMessage, bot.command_settings(null, f.language_code));
    ELSE
      vMessage := bot.command_settings(string_to_array(m.text, E'\n'), f.language_code);
    END IF;
  ELSE
    IF f.language_code = 'ru' THEN
      vMessage := 'Неизвестная команда.';
    ELSE
      vMessage := 'Unknown command.';
    END IF;
  END CASE;

  IF vMessage IS NOT NULL THEN
    PERFORM tg.send_message(r.id, c.id, vMessage, 'HTML');
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = tg, pg_temp;

--------------------------------------------------------------------------------
-- HEARTBEAT FUNCTION ----------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.BitcoinBalanceDetectorBot_heartbeat (
  pBotId        uuid
) RETURNS       void
AS $$
DECLARE
  r             record;
  u             record;
  e             record;

  i             interval;

  address       text;

  vMessage      text;
  vContext      text;
BEGIN
  SELECT * INTO r FROM bot.list WHERE id = pBotId;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  FOR u IN SELECT bot_id, chat_id, user_id FROM bot.data GROUP BY bot_id, chat_id, user_id
  LOOP
    address := null;

    SELECT make_interval(secs => value::int) INTO i
      FROM bot.data
     WHERE bot_id = u.bot_id
       AND chat_id = u.chat_id
       AND category = 'settings'
       AND key = 'interval'
       AND user_id = u.user_id;

    i := coalesce(i, INTERVAL '1 min');

    FOR e IN
      SELECT key, updated
        FROM bot.data
       WHERE bot_id = u.bot_id
         AND chat_id = u.chat_id
         AND user_id = u.user_id
         AND category = 'address'
         AND (Now() - updated) >= i
    LOOP
      address := coalesce(address || '|', '') || e.key;
    END LOOP;

    IF address IS NOT NULL THEN
      PERFORM http.fetch(format('https://blockchain.info/multiaddr?active=%s&n=0', address), 'GET', null, null, 'bot.blockchain_done', 'bot.blockchain_fail', 'blockchain', pBotId::text, 'multiaddr');
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
-- bot.blockchain_done ---------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.blockchain_done (
  pRequest  uuid
) RETURNS   void
AS $$
DECLARE
  r             record;
  e             record;
  m             record;

  uBotId        uuid;

  reply         jsonb;

  vMessage      text;
  vLanguageCode text;

  vOld          text;
  vNew          text;
BEGIN
  SELECT agent, profile, command, method, resource, status, status_text, response INTO r FROM http.fetch WHERE id = pRequest;

  uBotId := r.profile::uuid;

  SELECT language_code INTO vLanguageCode FROM bot.list WHERE id = uBotId;

  reply := r.response::jsonb;

  IF vLanguageCode = 'ru' THEN
    vMessage := E'Обнаружено изменение баланса:';
  ELSE
    vMessage := E'Balance Change Detected:';
  END IF;

  IF coalesce(r.status, 400) = 200 THEN

    IF r.command = 'multiaddr' THEN

      FOR e IN SELECT * FROM jsonb_to_recordset(reply->'addresses') AS x(address text, n_tx int, total_received double precision, total_sent double precision, final_balance double precision)
      LOOP
        vNew := format(E'%s\t%s\t%s\t%s', e.n_tx, to_char(e.total_received / 100000000, 'FM999990.00000000'), to_char(e.total_sent / 100000000, 'FM999990.00000000'), to_char(e.final_balance / 100000000, 'FM999990.00000000'));

        FOR m IN SELECT bot_id, chat_id, user_id FROM bot.data WHERE bot_id = uBotId AND category = 'address' AND key = e.address GROUP BY bot_id, chat_id, user_id
        LOOP
          SELECT value INTO vOld
            FROM bot.data
           WHERE bot_id = m.bot_id
             AND chat_id = m.chat_id
             AND user_id = m.user_id
             AND category = 'address'
             AND key = e.address;

          PERFORM bot.set_data('address', e.address, vNew, row_to_json(e)::jsonb, Now(), m.user_id, m.chat_id, m.bot_id);

          IF encode(digest(vOld, 'md5'), 'hex') != encode(digest(vNew, 'md5'), 'hex') THEN
            vMessage := concat(vMessage, E'\r\n\r\n<pre>', e.address, E'\r\n', vOld, E'\r\n', vNew, '</pre>');
            PERFORM tg.send_message(m.bot_id, m.user_id, vMessage, 'HTML');
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  ELSE
    IF reply ? 'message' THEN
      PERFORM WriteToEventLog('E', -1, reply->>'message', r.agent);
    END IF;
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.blockchain_fail ---------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.blockchain_fail (
  pRequest  uuid
) RETURNS   void
AS $$
DECLARE
  r         record;
BEGIN
  SELECT method, resource, error INTO r
    FROM http.request
   WHERE id = pRequest;

  PERFORM WriteToEventLog('E', -1, r.error);
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

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
  SET search_path = bot, pg_temp;

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
  SET search_path = bot, pg_temp;

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
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_help -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_help (
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

  FOR r IN SELECT * FROM get_data('help')
  LOOP
    vMessage := concat(coalesce(vMessage || E'\r\n', ''), concat('<code>', r.key, '</code>'), ' - ', r.value);
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
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_add --------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_add (
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
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_delete -----------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_delete (
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
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_list -------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_list (
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
      vMessage := 'Список пуст.';
    ELSE
      vMessage := 'The list is empty.';
    END IF;
  ELSE
    vMessage := vMessage || '</pre>';
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_check ------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_check (
  pLanguage text DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  i         interval;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  SELECT make_interval(secs => value::int) INTO i FROM bot.data WHERE category = 'settings' AND key = 'interval';

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
      vMessage := 'Список пуст.';
    ELSE
      vMessage := 'The list is empty.';
    END IF;
  END IF;

  RETURN vMessage;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- FUNCTION command_settings ---------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.command_settings (
  pSettings text[] DEFAULT null,
  pLanguage text DEFAULT null,
  pUpdated  timestamptz DEFAULT null
) RETURNS   text
AS $$
DECLARE
  r         record;
  vData     text[];
  count     int;
  vMessage  text;
BEGIN
  pLanguage := coalesce(pLanguage, 'en');
  count := 0;

  IF pSettings IS NULL THEN

    FOR r IN SELECT * FROM get_data('settings')
    LOOP
      vMessage := concat(coalesce(vMessage || E'\r\n\r\n', '<pre>'), r.key, '=', r.value);
      count := count + 1;
    END LOOP;

  ELSE

    FOR r IN SELECT unnest(pSettings) AS settings
    LOOP
      vData := string_to_array(r.settings, '=');

      IF array_length(vData, 1) = 2 THEN
        IF vData[1] = ANY (ARRAY['interval']) THEN

          IF vData[1] = 'interval' THEN
            PERFORM bot.set_data('settings', vData[1], vData[2], jsonb_build_object(vData[1], vData[2]::int), coalesce(pUpdated, Now()));
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
  SET search_path = bot, pg_temp;
