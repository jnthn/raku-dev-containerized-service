#!/usr/bin/env raku
use v6.d;
use Dev::ContainerizedService;

project 'r-d-cs-testing';
store 'default';

service 'postgres', :tag<13.0>, -> (:$conninfo, *%) {
    env 'DB_CONN_STRING', $conninfo;
}
