-- Drop Trade hub
DROP POLICY IF EXISTS my_market_watch_list on market_watch_list;
DROP TABLE market_watch_list;
DROP sequence seq_market_watchlist;
