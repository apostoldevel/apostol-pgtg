--------------------------------------------------------------------------------
-- BOT -------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- bot.list --------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.list (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         text NOT NULL,
  username      text NOT NULL,
  full_name     text NOT NULL,
  secret        text,
  language_code text DEFAULT 'en',
  created       timestamptz NOT NULL DEFAULT Now(),
  downtime      timestamptz NOT NULL DEFAULT Now()
);

COMMENT ON TABLE bot.list IS 'List of Telegram bots.';

COMMENT ON COLUMN bot.list.id IS 'Identifier';
COMMENT ON COLUMN bot.list.token IS 'Token';
COMMENT ON COLUMN bot.list.username IS 'Bot username';
COMMENT ON COLUMN bot.list.full_name IS 'Bot name';
COMMENT ON COLUMN bot.list.secret IS 'Secret code for authorization (if necessary).';
COMMENT ON COLUMN bot.list.language_code IS 'Language code';
COMMENT ON COLUMN bot.list.created IS 'Date and time of creation';
COMMENT ON COLUMN bot.list.downtime IS 'Downtime';

CREATE INDEX ON bot.list (downtime);

--------------------------------------------------------------------------------
-- bot.context -----------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.context (
  bot_id        uuid REFERENCES bot.list ON DELETE CASCADE,
  chat_id       bigint NOT NULL,
  user_id       bigint NOT NULL,
  command       text NOT NULL,
  text          text,
  data          jsonb,
  premium       bool DEFAULT false NOT NULL,
  updated       timestamptz NOT NULL DEFAULT Now(),
  PRIMARY KEY (bot_id, chat_id, user_id)
);

COMMENT ON TABLE bot.context IS 'Bot context.';

COMMENT ON COLUMN bot.context.bot_id IS 'Bot ID';
COMMENT ON COLUMN bot.context.chat_id IS 'Char ID';
COMMENT ON COLUMN bot.context.user_id IS 'User ID';
COMMENT ON COLUMN bot.context.command IS 'Current command';
COMMENT ON COLUMN bot.context.text IS 'Text';
COMMENT ON COLUMN bot.context.data IS 'Data';
COMMENT ON COLUMN bot.context.premium IS 'Premium user_id';
COMMENT ON COLUMN bot.context.updated IS 'Last updated';

CREATE INDEX ON bot.context (bot_id);
CREATE INDEX ON bot.context (premium);

--------------------------------------------------------------------------------
-- bot.data --------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.data (
  bot_id        uuid REFERENCES bot.list ON DELETE CASCADE,
  chat_id       bigint NOT NULL,
  user_id       bigint NOT NULL,
  category      text NOT NULL,
  key           text NOT NULL,
  value         text NOT NULL,
  data          jsonb,
  updated       timestamptz NOT NULL,
  PRIMARY KEY (bot_id, chat_id, user_id, category, key)
);

COMMENT ON TABLE bot.data IS 'Bot data.';

COMMENT ON COLUMN bot.data.bot_id IS 'Bot ID';
COMMENT ON COLUMN bot.data.chat_id IS 'Char ID';
COMMENT ON COLUMN bot.data.user_id IS 'User ID';
COMMENT ON COLUMN bot.data.category IS 'Category';
COMMENT ON COLUMN bot.data.key IS 'Key';
COMMENT ON COLUMN bot.data.value IS 'Value';
COMMENT ON COLUMN bot.data.data IS 'Data';
COMMENT ON COLUMN bot.data.updated IS 'Last updated';

CREATE INDEX ON bot.data (bot_id, chat_id, user_id, category);
CREATE INDEX ON bot.data (bot_id);
CREATE INDEX ON bot.data (user_id);
CREATE INDEX ON bot.data (category);
CREATE INDEX ON bot.data (key);

--------------------------------------------------------------------------------
-- bot.chat --------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.chat (
  bot_id        uuid REFERENCES bot.list ON DELETE CASCADE,
  chat_id       bigint NOT NULL,
  user_id       bigint NOT NULL,
  message_id    bigint NOT NULL,
  role          text NOT NULL,
  content       text NOT NULL,
  cost          numeric(12,0) DEFAULT 0 NOT NULL,
  datetime      timestamptz NOT NULL,
  PRIMARY KEY (bot_id, chat_id, message_id)
);

COMMENT ON TABLE bot.chat IS 'Bot chat.';

COMMENT ON COLUMN bot.chat.bot_id IS 'Bot ID';
COMMENT ON COLUMN bot.chat.chat_id IS 'Char ID';
COMMENT ON COLUMN bot.chat.user_id IS 'User ID';
COMMENT ON COLUMN bot.chat.message_id IS 'Message ID';
COMMENT ON COLUMN bot.chat.role IS 'Role';
COMMENT ON COLUMN bot.chat.content IS 'Content';
COMMENT ON COLUMN bot.chat.cost IS 'Cost in tokens';
COMMENT ON COLUMN bot.chat.datetime IS 'Date and time';

CREATE INDEX ON bot.chat (bot_id, chat_id, user_id, role);
CREATE INDEX ON bot.chat (bot_id, chat_id, role);
CREATE INDEX ON bot.chat (bot_id);
CREATE INDEX ON bot.chat (datetime);
