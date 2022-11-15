--------------------------------------------------------------------------------
-- bot.file --------------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE TABLE bot.file (
  file_id       text PRIMARY KEY,
  bot_id        uuid REFERENCES bot.list ON DELETE CASCADE,
  chat_id       int NOT NULL,
  user_id       int NOT NULL,
  file_name     text NOT NULL,
  file_path     text NOT NULL,
  file_size     integer DEFAULT 0,
  file_date     timestamptz,
  file_data     bytea,
  file_hash     text,
  file_text     text,
  file_type     text,
  file_link     text,
  load_date     timestamptz DEFAULT Now() NOT NULL
);

COMMENT ON TABLE bot.file IS 'File list.';

COMMENT ON COLUMN bot.file.bot_id IS 'Bot ID';
COMMENT ON COLUMN bot.file.chat_id IS 'Char ID';
COMMENT ON COLUMN bot.file.user_id IS 'User ID';
COMMENT ON COLUMN bot.file.file_name IS 'Name';
COMMENT ON COLUMN bot.file.file_path IS 'Path';
COMMENT ON COLUMN bot.file.file_size IS 'Size';
COMMENT ON COLUMN bot.file.file_date IS 'Date';
COMMENT ON COLUMN bot.file.file_data IS 'Data';
COMMENT ON COLUMN bot.file.file_hash IS 'Hash';
COMMENT ON COLUMN bot.file.file_text IS 'Text';
COMMENT ON COLUMN bot.file.file_type IS 'MIME type';
COMMENT ON COLUMN bot.file.file_link IS 'Link';
COMMENT ON COLUMN bot.file.load_date IS 'Loaded';

CREATE INDEX ON bot.file (bot_id, chat_id, user_id);
CREATE INDEX ON bot.file (file_hash);
CREATE INDEX ON bot.file (file_path, file_name);

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.ft_file()
RETURNS trigger AS $$
BEGIN
  NEW.file_hash := encode(digest(NEW.file_data, 'md5'), 'hex');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------

CREATE TRIGGER t_bot_file
  AFTER UPDATE ON bot.file
  FOR EACH ROW
  WHEN (OLD.file_data IS DISTINCT FROM NEW.file_data)
  EXECUTE PROCEDURE bot.ft_file();
