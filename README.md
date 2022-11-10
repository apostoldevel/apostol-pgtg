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

1. Build and install **pgTG**.

As a result, all messages addressed to your telegram bot through `nginx` will be redirected to `pgtg` and transferred to PostgreSQL for processing.

All you have to do is to implement the message handler in the `pgtg` database inside the `tg.webhook` function.

Implementation example:

~~~postgresql

~~~

Building and installation
-

### Dependencies:

1. C++ compiler;
2. [CMake](https://cmake.org) or a comprehensive development environment (IDE) with support for [CMake](https://cmake.org);
3. Library [libpq-dev](https://www.postgresql.org/download) (libraries and headers for C language frontend development);
4. Library [postgresql-server-dev-all](https://www.postgresql.org/download) (libraries and headers for C language backend development).

### Linux (Debian/Ubuntu)

To install a C++ compiler and a valid library on Ubuntu:
~~~
sudo apt-get install build-essential libssl-dev libcurl4-openssl-dev make cmake gcc g++
~~~

### PostgreSQL

To install PostgreSQL, follow the instructions at [this](https://www.postgresql.org/download/) link.

### Database

To install the database you need to run:

1. Write the name of the database in the db/sql/sets.conf file (default: pgtg)
1. Set passwords for Postgres users [libpq-pgpass](https://postgrespro.ru/docs/postgrespro/14/libpq-pgpass):
   ~~~
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
   ~~~
   sudo pg_ctlcluster 14 main reload
   ~~~   
1. Run:
   ~~~
   cd db/
   ./runme.sh --make
   ~~~

###### The `--make` option is required to install the database for the first time. Further, the installation script can be run either without parameters or with the `--install` parameter.

To install **pgTG** using Git, run:
~~~
git clone https://github.com/apostoldevel/apostol-pgtg.git
~~~

### Building:
~~~
cd apostol-pgtg
./configure
~~~

### Compilation and installation:
~~~
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
~~~
sudo systemctl start pgtg
~~~

To check the status, run:
~~~
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

~~~
docker build -t pgtg .
~~~

### Get

~~~
docker pull apostoldevel/pgtg
~~~

### Run

If assembled by yourself:
~~~
docker run -d -p 8080:8080 --rm --name pgtg pgtg
~~~

If you received a finished image:
~~~
docker run -d -p 8080:8080 --rm --name pgtg apostoldevel/pgtg
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