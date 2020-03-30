package Kuickres::GuiPlugin::RoomForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::RoomForm - Room Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::RoomForm;

=head1 DESCRIPTION

The Location Edit Form

=cut

has checkAccess => sub {
    my $self = shift;
    return $self->user->may('admin');
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Location Entry Form.

=cut



has formCfg => sub {
    my $self = shift;
    my $db = $self->user->db;

    return [
        $self->config->{type} eq 'edit' ? {
            key => 'room_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),

        {
            key => 'room_name',
            label => trm('Name'),
            widget => 'text',
            required => true,
            set => {
                required => true,
            },
        },
        {
            key => 'room_location',
            label => trm('Location'),
            required => true,
            widget => 'selectBox',
            cfg => {
                structure => $self->db->select(
                    'location',[\"location_id AS key",\"location_name AS title"],undef,'location_name'
                )->hashes->to_array
            }

        },
    ];
};

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = sub {
        my $self = shift;
        my $args = shift;
        if ($type eq 'add')  {
            $self->db->insert('room',{
                map { "room_".$_ => $args->{"room_".$_} } qw(
                    name location
                )
            });
        }
        else {
            $self->db->update('room', {
                map { 'room_'.$_ => $args->{'room_'.$_} } qw(
                    name location
                )
            },{ room_id => $args->{room_id}});
        }
        return {
            action => 'dataSaved'
        };
    };

    return [
        {
            label => $type eq 'edit'
               ? trm('Save Changes')
               : trm('Add Room'),
            action => 'submit',
            key => 'save',
            actionHandler => $handler
        }
    ];
};

has grammar => sub {
    my $self = shift;
    $self->mergeGrammar(
        $self->SUPER::grammar,
        {
            _vars => [ qw(type) ],
            type => {
                _doc => 'type of form to show: edit, add',
                _re => '(edit|add)'
            },
        },
    );
};

sub getAllFieldValues {
    my $self = shift;
    my $args = shift;
    return {} if $self->config->{type} ne 'edit';
    my $id = $args->{selection}{location_id};
    return {} unless $id;

    my $db = $self->db;
    my $data = $db->select('room','*',
        ,{room_id => $id})->hash;
    return $data;
}


1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
