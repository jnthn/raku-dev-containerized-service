#!/usr/bin/env raku
use v6.d;
use Dev::ContainerizedService;

service 'clickhouse', :tag<24.3>, -> (:$host, :$port, :$user, :$password, *%) {
    env 'CLICKHOUSE_HOST', $host;
    env 'CLICKHOUSE_PORT', $port;
    env 'CLICKHOUSE_USER', $user;
    env 'CLICKHOUSE_PASSWORD', $password;
}
