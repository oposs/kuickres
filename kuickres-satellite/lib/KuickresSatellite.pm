package KuickresSatellite;

use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {
    unshift @{$self->commands->namespaces},  __PACKAGE__.'::Command';
}
1;
