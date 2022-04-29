CREATE SEQUENCE seq_auth_session START 10000000;
ALTER SEQUENCE seq_auth_session OWNER TO auth;
create table auth_session (
                              session_id character varying(100) primary key DEFAULT nextval('seq_auth_session'),
                              auth_info character varying(2048),
                              char_info character varying(2048),
                              error character varying(100),
                              user_agent character varying(2048),
                              redirect_url character varying(2048) not null,
                              client_verify character varying(128) not null UNIQUE,
                              user_id character varying(20),
                              created timestamp not null default CURRENT_TIMESTAMP,
                              updated timestamp not null default CURRENT_TIMESTAMP,
                              committed numeric(1) not null default 0
);
ALTER TABLE auth_session OWNER TO auth;

create table character_token (
                                 access_token character varying(256) primary key,
                                 character_id integer not null,
                                 session_id character varying(100) references auth_session(session_id),
                                 token_type character varying(100) not null,
                                 scopes character varying(4000),
                                 created timestamp not null default CURRENT_TIMESTAMP,
                                 expires timestamp not null,
                                 refresh_token character varying(256),
                                 valid numeric(1) not null default 1
);
ALTER TABLE character_token OWNER TO auth;

CREATE SEQUENCE seq_users START 20000000;
ALTER SEQUENCE seq_users OWNER TO auth;
create table users (
                       user_id character varying(20) primary key DEFAULT concat('u',nextval('seq_users')),
                       character_id integer,
                       created timestamp not null default CURRENT_TIMESTAMP
);
ALTER TABLE users OWNER TO auth;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON users TO authenticated;
CREATE POLICY access_my_user ON users TO authenticated USING (user_id = current_user);

create table user_token (
                            token character varying(100) PRIMARY KEY,
                            user_id character varying(20) not null references users(user_id),
                            created timestamp not null default CURRENT_TIMESTAMP,
                            expires timestamp not null,
                            device character varying(1000) not null,
                            refresh_token character varying(100) references user_token(token),
                            valid numeric(1) not null default 1
);
ALTER TABLE user_token OWNER TO auth;

create table characters (
                            character_id integer primary key,
                            user_id character varying(20) references users(user_id),
                            owner_hash character varying (100) not null,
                            character_name character varying (100) not null,
                            created timestamp not null default CURRENT_TIMESTAMP
);
ALTER TABLE characters OWNER TO auth;
GRANT SELECT ON characters TO authenticated;
CREATE POLICY access_my_characters ON characters TO authenticated USING (user_id = current_user);


-- Trigger Procedure to create a new pg user
create or replace function create_user()
    RETURNS TRIGGER SECURITY DEFINER AS $$
BEGIN
    EXECUTE 'CREATE ROLE ' || NEW.user_id || ';';
    EXECUTE 'GRANT AUTHENTICATED TO ' || NEW.user_id || ';';
    EXECUTE 'GRANT ' || NEW.user_id || ' TO esi;';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
-- insert character token trigger
CREATE TRIGGER insert_user
    AFTER INSERT ON users
    FOR EACH ROW
EXECUTE PROCEDURE create_user();


-- Trigger Procedure to send character_info auth event
create or replace function notify_character_info()
    RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('auth', '{"event": "character_info", "char_info": ' || NEW.char_info || ', "auth_info": ' || NEW.auth_info|| '}');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
-- update auth session with char info trigger
CREATE TRIGGER update_auth_session
    AFTER UPDATE ON auth_session
    FOR EACH ROW
    WHEN (NEW.char_info is not null AND OLD.char_info is null)
EXECUTE PROCEDURE notify_character_info();

create or replace function random_string(IN plength int)
    RETURNS varchar AS $$
DECLARE
    alphanumeric constant varchar := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    i int;
    idx int;
    result varchar := '';
BEGIN
    FOR i IN 1.. plength LOOP
            idx := (random() * 61 + 1)::INT;
            result := result || substring(alphanumeric, idx, 1);
        END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;


CREATE TYPE auth_info AS (
                             access_token varchar,
                             token_type varchar,
                             expires_in integer,
                             refresh_token varchar
                         );


CREATE TYPE char_info AS (
                             "CharacterID" integer,
                             "CharacterName" varchar,
                             "Scopes" varchar,
                             "CharacterOwnerHash" varchar,
                             "ExpiresOn" timestamp
                         );

CREATE OR REPLACE FUNCTION user_sign_in(IN pclient_verify varchar, IN puser_agent varchar, IN pdevice varchar)
    RETURNS varchar AS $$
DECLARE
    lsession_id varchar;
    lauth_info varchar;
    lchar_info varchar;
    luser_agent varchar;
    lcharacter_id integer;
    lcharacter_name varchar;
    lcharacter_expires timestamp;
    lscopes varchar;
    lowner_hash varchar;
    lowner_hash_old varchar;
    luser_id varchar;
    llink_user_id varchar;
    luser_token varchar;
    lexpires timestamp;
BEGIN
    -- Maybe, think of a better validation
    if pclient_verify is null or puser_agent is null or pdevice is null then
        RAISE EXCEPTION 'pclient_verify, puser_agent and pdevice are required % % %', pclient_verify, puser_agent, pdevice;
    end if;

    -- fetch and commit the session
    select session_id, auth_info, char_info, user_agent, user_id
    into lsession_id, lauth_info, lchar_info, luser_agent, llink_user_id
    from auth_session
    where client_verify = pclient_verify and committed = 0;

    if lsession_id is null then
        RAISE EXCEPTION 'No authorization to verify %', pclient_verify;
    end if;

    -- Commit session so it can not be used again
    update auth_session set committed = 1, updated = CURRENT_TIMESTAMP where session_id = lsession_id;

    if puser_agent <> luser_agent then
        RAISE EXCEPTION 'No authorization to verify, my friend';
    end if;

    -- Parse JSON parts
    select "CharacterID", "CharacterName", "Scopes", "CharacterOwnerHash", "ExpiresOn"
    into lcharacter_id, lcharacter_name, lscopes, lowner_hash, lcharacter_expires
    from json_populate_record(null::char_info, lchar_info::json);

    if lcharacter_id is null or lowner_hash is null then
        RAISE EXCEPTION 'Character info requires CharacterID and CharacterOwnerHash %', lchar_info;
    end if;

    -- Check if the character already exists
    select owner_hash, user_id into lowner_hash_old, luser_id
    from characters
    where character_id = lcharacter_id;

    -- The character did not belong to any users, proceed adding to a new or link user
    if luser_id is null then
        -- New user
        if llink_user_id is null then
            -- This is a new character, create user record first
            insert into users (character_id) values (lcharacter_id) returning user_id into luser_id;
        else
            -- Link user
            luser_id := llink_user_id;
        end if;
        -- Now finish with character
        insert into characters (character_id, user_id, owner_hash, character_name)
        values (lcharacter_id, luser_id, lowner_hash, lcharacter_name)
        on conflict (character_id)
            do
                update set user_id = luser_id, owner_hash = lowner_hash;
    else
        -- Signing in to existing user
        if llink_user_id is null then
            -- Character was transferred to another account, unlink the old one
            if lowner_hash <> lowner_hash_old then
                -- Unlink character from the old user
                update users set character_id = null where user_id = luser_id;
                -- Create new user for this character
                insert into users (character_id) values (lcharacter_id) returning user_id into luser_id;
                -- Update character to new user
                update characters set user_id = luser_id, owner_hash = lowner_hash where character_id = lcharacter_id;
            end if;
        else
            -- Linking to existing user but the character already belongs to another user.
            -- The only valid scenario would be if Character was transferred to another account so unlink it from previous owner
            if lowner_hash <> lowner_hash_old then
                -- Unlink character from the old user
                update users set character_id = null where user_id = luser_id;
                -- Link user
                luser_id := llink_user_id;
                -- Update character to new user
                update characters set user_id = luser_id, owner_hash = lowner_hash where character_id = lcharacter_id;
            else
                RAISE EXCEPTION 'This character already belongs to another user. Log in as character and unlink it before adding to this user. %', lcharacter_id;
            end if;
        end if;
    end if;

    -- at this point, we should be done with user. Just double check for dev(me) mistake
    if luser_id is null then
        RAISE EXCEPTION 'User was not created for character(sorry about that) %', lcharacter_id;
    end if;

    -- Create character_token record
    PERFORM from insert_character_token(lcharacter_id, lsession_id, lauth_info, lscopes);

    -- The last step - User Token
    select token, expires
    into luser_token, lexpires
    from user_token
    where user_id = luser_id
      and device = pdevice
      and valid = 1
    order by expires desc
    limit 1;

    -- See if the token already exists
    if lexpires is null or lexpires <= CURRENT_TIMESTAMP then
        insert into user_token(token, user_id, device, expires, refresh_token)
        values (random_string(30), luser_id, pdevice, CURRENT_TIMESTAMP + interval '1 day', luser_token)
        returning token into luser_token;
    end if;
    return '{"user_id": "' || luser_id || '", "auth_token": "' || luser_token || '"}';
END;
$$ LANGUAGE plpgsql;

-- Exchange user token for user id if session is valid
CREATE OR REPLACE FUNCTION exchange_user_token(IN paccess_token varchar, IN pdevice varchar) RETURNS varchar
    SECURITY DEFINER AS $$
select user_id
from auth.user_token
where token = paccess_token
  and device = pdevice
  and valid = 1
  and expires > CURRENT_TIMESTAMP
order by expires desc
limit 1;
$$ LANGUAGE SQL;
GRANT EXECUTE ON FUNCTION exchange_user_token TO esi;

-- Exchange user token for user id if session is valid
CREATE OR REPLACE FUNCTION exchange_character_token(IN puser_id varchar, IN pcharacter_id integer, IN pscope varchar) RETURNS varchar
    SECURITY DEFINER AS $$
select access_token
from auth.character_token ct
         join auth.characters c on ct.character_id = c.character_id
    and c.user_id = puser_id
where ct.character_id = pcharacter_id
  and ct.valid = 1
  and ct.expires > CURRENT_TIMESTAMP
  and scopes like '%' || pscope || '%'
order by ct.created desc
limit 1;
$$ LANGUAGE SQL;
GRANT EXECUTE ON FUNCTION exchange_character_token TO esi;

-- User Authentication
CREATE OR REPLACE FUNCTION authenticate(IN paccess_token varchar, IN pdevice varchar, IN set_session boolean DEFAULT true)
    RETURNS varchar AS $$
DECLARE
    luser_id varchar;
BEGIN
    if set_session then
        SET SESSION AUTHORIZATION DEFAULT;
    end if;
    if paccess_token is null or pdevice is null then
        RAISE EXCEPTION 'User was unable to authenticate';
    end if;

    luser_id := auth.exchange_user_token(paccess_token, pdevice);

    -- make sure user is found
    if luser_id is null then
        RAISE EXCEPTION 'User was unable to authenticate';
    end if;
    -- Set session to the user id
    if set_session then
        EXECUTE 'SET SESSION AUTHORIZATION ' || luser_id || ';';
        return current_user;
    else
        return luser_id;
    end if;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION authenticate TO esi;

-- User Authentication with character info
CREATE OR REPLACE FUNCTION authenticate_character_in_scope(IN puser_token varchar, IN pdevice varchar, IN pcharacter_id integer, IN pscope varchar)
    RETURNS varchar AS $$
DECLARE
    luser_id varchar;
    lcharacter_token varchar;
BEGIN
    if pcharacter_id is null or pscope is null then
        RAISE EXCEPTION 'Character was unable to authenticate';
    end if;

    -- exchange to user id
    luser_id := auth.authenticate(puser_token, pdevice, false);

    if luser_id is null then
        RAISE EXCEPTION 'User was unable to authenticate';
    end if;

    lcharacter_token := auth.exchange_character_token(luser_id, pcharacter_id, pscope);

    if lcharacter_token is not null then
        EXECUTE 'SET ROLE ' || luser_id || ';';
    end if;
    return lcharacter_token;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION authenticate_character_in_scope TO esi;

-- End authentication
CREATE OR REPLACE FUNCTION end_authentication()
    RETURNS varchar AS $$
BEGIN
    SET SESSION AUTHORIZATION DEFAULT;
    return current_user;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION end_authentication TO esi;

-- User token refresh
CREATE OR REPLACE FUNCTION refresh_user_token(IN paccess_token varchar, IN pdevice varchar)
    RETURNS varchar AS $$
DECLARE
    luser_id varchar;
    luser_token varchar;
BEGIN
    if paccess_token is null or pdevice is null then
        RAISE EXCEPTION 'User was unable to authenticate';
    end if;

    -- Get the last used and expired less than a week ago
    select user_id
    into luser_id
    from user_token
    where token = paccess_token
      and device = pdevice
      and valid = 1
      and expires < CURRENT_TIMESTAMP
      and expires + (interval '1 week') > CURRENT_TIMESTAMP
    order by expires desc
    limit 1;

    -- make sure user is found
    if luser_id is null then
        RAISE EXCEPTION 'User was unable to authenticate';
    end if;

    insert into user_token(token, user_id, device, expires, refresh_token)
    values (random_string(30), luser_id, pdevice, CURRENT_TIMESTAMP + interval '1 day', paccess_token)
    returning token into luser_token;

    return '{"user_id": "' || luser_id || '", "auth_token": "' || luser_token || '"}';
END;
$$ LANGUAGE plpgsql;

-- Fetch character token
CREATE OR REPLACE FUNCTION get_character_token(IN pcharacter_id varchar, IN puser_id varchar default current_user)
    RETURNS varchar AS $$
DECLARE
    lcharacter_token varchar;
    lexpires timestamp;
BEGIN
    select ct.character_token, ct.valid, ct.expires
    into lcharacter_token, lexpires
    from character_token ct
             join characters cr
                  on cr.character_id = ct.character_id
                      and cr.character_id = pcharacter_id
                      and cr.user_id = puser_id
    where ct.valid = 1
    order by ct.created
    limit 1;

    if lcharacter_token is not null then
        return '{"user_id": "' || puser_id || '", "character_id": "' || pcharacter_id || '", "user_id": "' || puser_id || '", "character_token": "' || lcharacter_token || '", "expires": "' || lexpires || '"}';
    else
        return null;
    end if;
END;
$$ LANGUAGE plpgsql;

-- Insert character token
CREATE OR REPLACE FUNCTION insert_character_token(IN pcharacter_id integer, IN lsession_id varchar, IN pauth_info varchar, IN pscopes varchar default null)
    RETURNS varchar AS $$
DECLARE
    lscopes varchar;
    lauth_info auth_info;
BEGIN
    -- parse auth info
    select * into lauth_info
    from json_populate_record(null::auth_info, pauth_info::json);

    -- copy scopes from previous token if available
    if pscopes is null and lauth_info.refresh_token is not null then
        select scopes into lscopes
        from character_token
        where access_token = lauth_info.refresh_token;
    else
        lscopes := pscopes;
    end if;

    -- Insert new token
    insert into character_token (access_token, character_id, session_id, token_type, scopes, expires, refresh_token)
    values (lauth_info.access_token, pcharacter_id, lsession_id, lauth_info.token_type, lscopes,
            current_timestamp + lauth_info.expires_in * interval '1 second', lauth_info.refresh_token);
    return 'OK';
END;
$$ LANGUAGE plpgsql;

ALTER FUNCTION authenticate OWNER TO auth;
ALTER FUNCTION end_authentication OWNER TO auth;
ALTER FUNCTION get_character_token OWNER TO auth;
ALTER FUNCTION insert_character_token OWNER TO auth;
ALTER FUNCTION random_string OWNER TO auth;
ALTER FUNCTION refresh_user_token OWNER TO auth;
ALTER FUNCTION user_sign_in OWNER TO auth;
ALTER FUNCTION authenticate_character_in_scope OWNER TO auth;
ALTER FUNCTION exchange_user_token OWNER TO auth;
ALTER FUNCTION exchange_character_token OWNER TO auth;
