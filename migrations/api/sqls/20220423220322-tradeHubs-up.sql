-- Market Watch List
CREATE SEQUENCE seq_market_watchlist START 12000000;
ALTER SEQUENCE seq_market_watchlist OWNER TO api;
CREATE TABLE market_watch_list
(
    watchlist_id varchar(20) PRIMARY KEY DEFAULT concat('mw',nextval('seq_market_watchlist')),
    name varchar(1024) not null,
    description varchar(1024),
    items jsonb not null,
    price_filter numeric(2,2),
    user_id varchar(20) not null references auth.users(user_id) DEFAULT current_user,
    created timestamp not null DEFAULT CURRENT_TIMESTAMP,
    updated timestamp not null DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE market_watch_list OWNER TO api;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE market_watch_list TO authenticated;
ALTER TABLE market_watch_list ENABLE ROW LEVEL SECURITY;
CREATE POLICY my_market_watch_list ON market_watch_list TO authenticated USING (user_id = current_user);
