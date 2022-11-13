--------------------------------------------------------------------------------
-- VIEW EventLog ---------------------------------------------------------------
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW EventLog (Id, Type, TypeName, DateTime, TimeStamp, UserName,
  Code, Event, Text, Category
)
AS
  SELECT id, type,
         CASE
         WHEN type = 'M' THEN 'Information'
         WHEN type = 'W' THEN 'Warning'
         WHEN type = 'E' THEN 'Error'
         WHEN type = 'D' THEN 'Debug'
         END,
         datetime, timestamp, username, code, event, text, category
    FROM bot.log;

GRANT SELECT ON EventLog TO :username;
