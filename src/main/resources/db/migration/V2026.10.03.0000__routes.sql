CREATE TABLE IF NOT EXISTS routes (
    origin_latitude REAL NOT NULL,
    origin_longitude REAL NOT NULL,
    destination_latitude REAL NOT NULL,
    destination_longitude REAL NOT NULL,
    estimate_time TIMESTAMP NOT NULL,
    duration BIGINT NOT NULL,
    static_duration BIGINT NOT NULL,
    distance INT NOT NULL,
    CONSTRAINT pk_routes PRIMARY KEY (estimate_time, origin_latitude, origin_longitude, destination_latitude, destination_longitude)
);
