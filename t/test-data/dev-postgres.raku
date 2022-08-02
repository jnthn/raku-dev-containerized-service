#!/usr/bin/env raku
use v6.d;
use Dev::ContainerizedService;

service 'postgres', :tag<13.0>, -> (:$conninfo, *%) {
    env 'DB_CONN_STRING', $conninfo;
}
