--------------------------------------------------------------------------------
-- tg.bot ----------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE tg.bot (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         text NOT NULL,
  username      text NOT NULL,
  full_name     text NOT NULL,
  secret        text,
  language_code text DEFAULT 'en',
  created       timestamptz DEFAULT clock_timestamp() NOT NULL
);

COMMENT ON TABLE tg.bot IS 'Telegram bot.';

COMMENT ON COLUMN tg.bot.id IS 'Идентификатор';
COMMENT ON COLUMN tg.bot.token IS 'Маркер доступа';
COMMENT ON COLUMN tg.bot.username IS 'Пользователь';
COMMENT ON COLUMN tg.bot.full_name IS 'Наименование';
COMMENT ON COLUMN tg.bot.secret IS 'Секретный код';
COMMENT ON COLUMN tg.bot.language_code IS 'Код языка';
COMMENT ON COLUMN tg.bot.created IS 'Дата и время создания';
