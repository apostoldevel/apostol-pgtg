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
  created       timestamptz DEFAULT clock_timestamp() NOT NULL
);

COMMENT ON TABLE bot.list IS 'List of Telegram bots.';

COMMENT ON COLUMN bot.list.id IS 'Identifier';
COMMENT ON COLUMN bot.list.token IS 'Token';
COMMENT ON COLUMN bot.list.username IS 'Bot username';
COMMENT ON COLUMN bot.list.full_name IS 'Bot name';
COMMENT ON COLUMN bot.list.secret IS 'Secret code for authorization (if necessary).';
COMMENT ON COLUMN bot.list.language_code IS 'Language code';
COMMENT ON COLUMN bot.list.created IS 'Date and time of creation';
