--------------------------------------------------------------------------------
-- bot.new_file ----------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.new_file (
  pFileId       text,
  pBotId        uuid,
  pChatId       bigint,
  pUserId       bigint,
  pName		    text,
  pPath		    text,
  pSize		    integer,
  pDate		    timestamptz,
  pData		    bytea DEFAULT null,
  pHash		    text DEFAULT null,
  pText		    text DEFAULT null,
  pType		    text DEFAULT null,
  pLink		    text DEFAULT null
) RETURNS	    void
AS $$
BEGIN
  INSERT INTO bot.file (file_id, bot_id, chat_id, user_id, file_name, file_path, file_size, file_date, file_data, file_hash, file_text, file_type, file_link)
  VALUES (pFileId, pBotId, pChatId, pUserId, pName, pPath, pSize, pDate, pData, pHash, pText, pType, pLink);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.update_file -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.update_file (
  pFileId       text,
  pName		    text DEFAULT null,
  pPath		    text DEFAULT null,
  pSize		    integer DEFAULT null,
  pDate		    timestamptz DEFAULT null,
  pData		    bytea DEFAULT null,
  pHash		    text DEFAULT null,
  pText		    text DEFAULT null,
  pType		    text DEFAULT null,
  pLink		    text DEFAULT null,
  pLoad		    timestamptz DEFAULT null
) RETURNS	    void
AS $$
BEGIN
  UPDATE bot.file
     SET file_path = coalesce(pPath, file_path),
         file_name = coalesce(pName, file_name),
         file_size = coalesce(pSize, file_size),
         file_date = coalesce(pDate, file_date),
         file_data = coalesce(pData, file_data),
         file_hash = coalesce(pHash, file_hash),
         file_text = NULLIF(coalesce(pText, file_text, ''), ''),
         file_type = NULLIF(coalesce(pType, file_type, ''), ''),
         file_link = NULLIF(coalesce(pLink, file_link, ''), ''),
         load_date = coalesce(pLoad, load_date)
   WHERE file_id = pFileId;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.set_file ----------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.set_file (
  pFileId       text,
  pBotId        uuid DEFAULT null,
  pChatId       bigint DEFAULT null,
  pUserId       bigint DEFAULT null,
  pName		    text DEFAULT null,
  pPath		    text DEFAULT null,
  pSize		    integer DEFAULT null,
  pDate		    timestamptz DEFAULT null,
  pData		    bytea DEFAULT null,
  pHash		    text DEFAULT null,
  pText		    text DEFAULT null,
  pType		    text DEFAULT null,
  pLink		    text DEFAULT null,
  pLoad		    timestamptz DEFAULT null
) RETURNS       int
AS $$
BEGIN
  IF coalesce(pSize, 0) >= 0 THEN
    PERFORM FROM bot.file WHERE file_id = pFileId;
    IF NOT FOUND THEN
      PERFORM bot.new_file(pFileId, pBotId, pChatId, pUserId, pName, pPath, pSize, pDate, pData, pHash, pText, pType, pLink);
    ELSE
      PERFORM bot.update_file(pFileId, pName, pPath, pSize, pDate, pData, pHash, pText, pType, pLink, pLoad);
    END IF;
  ELSE
    PERFORM bot.delete_file(pFileId);
  END IF;

  RETURN pSize;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.delete_file -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.delete_file (
  pFileId       text
) RETURNS       boolean
AS $$
BEGIN
  DELETE FROM bot.file
   WHERE file_id = pFileId;
  RETURN FOUND;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;

--------------------------------------------------------------------------------
-- bot.clear_files -------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bot.clear_files (
  pBotId        uuid,
  pChatId       bigint,
  pUserId       bigint
) RETURNS       void
AS $$
BEGIN
  DELETE FROM bot.file
   WHERE bot_id = pBotId
     AND chat_id = pChatId
     AND user_id = pUserId;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = bot, pg_temp;
