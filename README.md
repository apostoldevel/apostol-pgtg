# Telegram bot in Postgres (pgTG)

Here you will find everything you need to implement a telegram bot in the PL/pgSQL programming language.

How is it possible?
-

This was made possible thanks to the [Apostol](https://github.com/apostoldevel/apostol) project and the [PGFetch](https://github.com/apostoldevel/module-PGFetch) (Postgres Fetch) module.

**Sequencing**
-

1. Set the [WebHook](https://core.telegram.org/bots/api#setwebhook) in your Telegram bot settings:
   * [Setting your Telegram Bot WebHook the easy way](https://xabaras.medium.com/setting-your-telegram-bot-webhook-the-easy-way-c7577b2d6f72)
     * Format URL:
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
   SELECT tg.add_bot('00000000-0000-4000-8000-000000000001', 'API_TOKEN', 'USERNAME_bot', 'Bot Name', null, 'en');
   ~~~
6. Create a message handler function in the `tg` schema. It must match the name of your bot when registering it in step #5 in the example it is `USERNAME_bot`.

**WARNING**: Replace `USERNAME_bot` with your bot's real name everywhere.

#### Handler function example:
<details>
  <summary>tg.USERNAME_bot</summary>

~~~postgresql
CREATE OR REPLACE FUNCTION tg.USERNAME_bot (
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
  SELECT * INTO b FROM tg.bot WHERE id = bot_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT * INTO r FROM jsonb_to_record(body) AS x(message jsonb, update_id double precision);
  SELECT * INTO m FROM jsonb_to_record(r.message) AS x(chat jsonb, date double precision, "from" jsonb, text text, entities jsonb, update_id double precision);
  SELECT * INTO c FROM jsonb_to_record(m.chat) AS x(id int, type text, username text, last_name text, first_name text);
  SELECT * INTO f FROM jsonb_to_record(m."from") AS x(id int, is_bot bool, username text, last_name text, first_name text, language_code text);

  CASE m.text
  WHEN '/start' THEN
    message := format('Hello! My name is %s.', b.full_name);
  WHEN '/help' THEN
    message := 'Unfortunately, I can''t help you yet.';
  WHEN '/settings' THEN
    message := 'Not applicable.';
  ELSE
    message := 'Unknown command.';
  END CASE;

  PERFORM tg.send_message(bot_id, c.id, message);

  RETURN true;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = tg, pg_temp;
~~~
</details> 

As a result, all messages addressed to your telegram bot through `nginx` will be redirected to `pgtg` and transferred to PostgreSQL for processing.

**All you have to do is to implement a function in the `pgtg` database to process messages coming from telegrams.**

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