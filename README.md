# Telegram bot in Postgres (pgTG)

Here you will find everything you need to implement a telegram bot in the PL/pgSQL programming language.

How is it possible?
-

This was made possible thanks to the [Apostol](https://github.com/apostoldevel/apostol) project and the [PGFetch](https://github.com/apostoldevel/module-PGFetch) (Postgres Fetch) module.

How it works?
-

All messages addressed to your telegram bot through [WebHook](https://core.telegram.org/bots/api#setwebhook) will be redirected to `pgtg` and passed to PostgreSQL for processing.

All you need to do is to implement a handler function to process messages coming from telegrams, as described below.

**Sequencing**
-

1. Set the [WebHook](https://core.telegram.org/bots/api#setwebhook) in your Telegram bot settings:
   * [Setting your Telegram Bot WebHook the easy way](https://xabaras.medium.com/setting-your-telegram-bot-webhook-the-easy-way-c7577b2d6f72)
      * URL format:
        ~~~
        https://you.domain.org/api/v1/webhook/00000000-0000-4000-8000-000000000001
        ~~~
         * `you.domain.org` - You domain name;


2. Configure [Nginx](https://nginx.org) so that telegram requests are redirected to **pgTG** on port `4980`:

    <details>
      <summary>Example</summary>

      ~~~
      server {
        listen 443 ssl;
        server_name you.domain.org;

        ssl_certificate     /etc/ssl/certs/you.domain.crt;
        ssl_certificate_key /etc/ssl/private/you.domain.key;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;
      
        location / {
          proxy_pass http://127.0.0.1:4980;
          proxy_http_version 1.1;
          proxy_set_header Host $host;
          proxy_set_header Connection "keep-alive";
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
      }
      ~~~
    </details> 


3. Build and install **pgTG**.


4. Connect to the database `pgtg`:
   ~~~shell
   sudo -u postgres psql -d pgtg -U http
   ~~~


5. Register your bot:
   ~~~postgresql
   SELECT bot.add('00000000-0000-4000-8000-000000000001', '<API_TOKEN>', '<BOT_USERNAME>', '<BOT_NAME>', null, 'en');
   ~~~
   * `API_TOKEN` - Telegram bot API Token. Example: `0000000000:AAxxxXXXxxxXXXxxxXXXxxxXXXxxxXXXxxx`;
   * `BOT_USERNAME` - Telegram bot username. Example: `BitcoinBalanceDetectorBot`;
   * `BOT_NAME` - Telegram bot name. Example: `Bitcoin Balance Detector`.


6. Create a `Webhook` function in the `bot` schema:
   * The function name must start with your bot username and end with `_webhook`.


7. Create a `Heartbeat` function in the `bot` schema:
   * The function name must start with your bot username and end with `_heartbeat`.


### Webhook function example:
<details>
  <summary>BitcoinBalanceDetectorBot_webhook</summary>

~~~postgresql
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
~~~
</details> 

### Heartbeat function example:
<details>
  <summary>BitcoinBalanceDetectorBot_heartbeat</summary>

~~~postgresql
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
      PERFORM http.fetch(format('https://blockchain.info/multiaddr?active=%s&n=0', address), 'GET', null, null, 'bot.blockchain_done', 'bot.blockchain_fail', 'blockchain', u.user_id::text, 'multiaddr');
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
~~~
</details> 

Building and installation
-

### Dependencies:

1. C++ compiler;
2. [CMake](https://cmake.org) or a comprehensive development environment (IDE) with support for [CMake](https://cmake.org);
3. Library [libpq-dev](https://www.postgresql.org/download) (libraries and headers for C language frontend development);
4. Library [postgresql-server-dev-all](https://www.postgresql.org/download) (libraries and headers for C language backend development).

### Linux (Debian/Ubuntu)

To install a C++ compiler and a valid library on Ubuntu:
~~~shell
sudo apt-get install build-essential libssl-dev libcurl4-openssl-dev make cmake gcc g++
~~~

### PostgreSQL

To install PostgreSQL, follow the instructions at [this](https://www.postgresql.org/download/) link.

### Database

To install the database you need to run:

1. Write the name of the database in the db/sql/sets.conf file (default: pgtg)
1. Set passwords for Postgres users [libpq-pgpass](https://postgrespro.ru/docs/postgrespro/14/libpq-pgpass):
   ~~~shell
   sudo -iu postgres -H vim .pgpass
   ~~~
   ~~~
   *:*:*:http:http
   ~~~
1. Specify in the settings file `/etc/postgresql/14/main/pg_hba.conf`:
   ~~~
   # TYPE  DATABASE        USER            ADDRESS                 METHOD
   local	pgtg		http					md5
   ~~~
1. Apply settings:
   ~~~shell
   sudo pg_ctlcluster 14 main reload
   ~~~   
1. Run:
   ~~~shell
   cd db/
   ./runme.sh --make
   ~~~

###### The `--make` option is required to install the database for the first time. Further, the installation script can be run either without parameters or with the `--install` parameter.

To install **pgTG** using Git, run:
~~~shell
git clone https://github.com/apostoldevel/apostol-pgtg.git
~~~

### Building:
~~~shell
cd apostol-pgtg
./configure
~~~

### Compilation and installation:
~~~shell
cd cmake-build-release
make
sudo make install
~~~

By default, the `pgtg` binary will be installed to:
~~~
/usr/sbin
~~~

The configuration file and the corresponding files for operation, depending on the installation configuration, are installed in:
~~~
/etc/pgtg
~~~

Run
-

**`pgtg`** is a Linux system service (daemon).
To manage **`pgtg`**, use standard service management commands.

To run `pgtg` run:
~~~shell
sudo systemctl start pgtg
~~~

To check the status, run:
~~~shell
sudo systemctl status pgtg
~~~

The result should be **something** like this:
~~~
● pgtg.service - Telegram bot in Postgres
     Loaded: loaded (/etc/systemd/system/pgtg.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2022-11-10 01:02:00 MSK; 4s ago
    Process: 57641 ExecStartPre=/usr/bin/rm -f /run/pgtg.pid (code=exited, status=0/SUCCESS)
    Process: 57647 ExecStartPre=/usr/sbin/pgtg -t (code=exited, status=0/SUCCESS)
    Process: 57648 ExecStart=/usr/sbin/pgtg (code=exited, status=0/SUCCESS)
   Main PID: 57649 (pgtg)
      Tasks: 2 (limit: 9528)
     Memory: 6.6M
     CGroup: /system.slice/pgtg.service
             ├─57649 pgtg: master process /usr/sbin/pgtg
             └─57650 pgtg: worker process ("pg fetch", "web server")
~~~

Docker
-

You can build the image yourself or get it ready-made from the docker hub:

### Collect

~~~shell
docker build -t pgtg .
~~~

### Get

~~~shell
docker pull apostoldevel/pgtg
~~~

### Run

If assembled by yourself:
~~~shell
docker run -d -p 4980:4980 --rm --name pgtg pgtg
~~~

If you received a finished image:
~~~shell
docker run -d -p 4980:4980 --rm --name pgtg apostoldevel/pgtg
~~~

Swagger UI will be available at http://localhost:4980 or http://host-ip:4980 in your browser.

### **Management**

You can control **`pgtg`** with signals.
The default master process number is written to the `/run/pgtg.pid` file.
You can change the name of this file during build configuration or in `pgtg.conf` section `[daemon]` key `pid`.

The master process supports the following signals:

| Signal | Action |
|---------|------------------|
|TERM, INT|quick completion|
|QUIT |smooth termination|
|HUP |change configuration, start new workflows with new configuration, gracefully terminate old workflows|
|WINCH |smooth shutdown of workflows|

You do not need to manage workflows separately. However, they also support some signals:

| Signal | Action |
|---------|------------------|
|TERM, INT|quick completion|
|QUIT |smooth termination|