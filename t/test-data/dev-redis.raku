#!/usr/bin/env raku
use v6.d;
use Dev::ContainerizedService;

service 'redis', :tag<7.0>, -> (:$host, :$port) {
    env 'REDIS_HOST', $host;
    env 'REDIS_PORT', $port;
}
