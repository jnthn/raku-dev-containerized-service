use v6.d;
use Dev::ContainerizedService::Spec;

class Dev::ContainerizedService::Spec::Redis does Dev::ContainerizedService::Spec {
    has Int $!port = self.generate-port;

    method docker-container(--> Str) { 'redis' }

    method default-docker-tag(--> Str) { 'latest' }

    method docker-options(--> Positional) {
        [
            '-p', "127.0.0.1:$!port:6379"
        ]
    }

    method ready(Str :$name --> Promise) {
        self.ready-by-connectability('127.0.0.1', $!port)
    }

    method service-data(--> Associative) {
        { :host<127.0.0.1>, :$!port }
    }
}
