--------------------------------------------------------------------------------
-- bot.log ---------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.log (
    id          bigserial PRIMARY KEY NOT NULL,
    type        char DEFAULT 'M' NOT NULL CHECK (type IN ('M', 'W', 'E', 'D')),
    datetime	timestamptz DEFAULT clock_timestamp() NOT NULL,
    timestamp	timestamptz DEFAULT Now() NOT NULL,
    username	text NOT NULL,
    code        integer NOT NULL,
    event		text NOT NULL,
    text        text NOT NULL,
    category    text
);

COMMENT ON TABLE bot.log IS 'Журнал событий.';

COMMENT ON COLUMN bot.log.id IS 'Идентификатор';
COMMENT ON COLUMN bot.log.type IS 'Тип события';
COMMENT ON COLUMN bot.log.datetime IS 'Дата и время события';
COMMENT ON COLUMN bot.log.timestamp IS 'Дата и время транзакции';
COMMENT ON COLUMN bot.log.username IS 'Имя пользователя';
COMMENT ON COLUMN bot.log.code IS 'Код события';
COMMENT ON COLUMN bot.log.event IS 'Событие';
COMMENT ON COLUMN bot.log.text IS 'Текст';
COMMENT ON COLUMN bot.log.category IS 'Категория';

CREATE INDEX ON bot.log (type);
CREATE INDEX ON bot.log (username);
CREATE INDEX ON bot.log (code);
CREATE INDEX ON bot.log (event);
CREATE INDEX ON bot.log (category);

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ft_log_insert()
RETURNS trigger AS $$
BEGIN
  NEW.datetime := clock_timestamp();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = kernel, pg_temp;

--------------------------------------------------------------------------------

CREATE TRIGGER t_log_insert
  BEFORE INSERT ON bot.log
  FOR EACH ROW
  EXECUTE PROCEDURE ft_log_insert();
