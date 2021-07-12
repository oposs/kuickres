package Kuickres::GuiPlugin::EquipmentForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::RoomForm - Equipment Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::EquipmentForm;

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
    return shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Location Entry Form.

=cut



has formCfg => sub {
    my $self = shift;
    my $db = $self->user->db;

    return [
        $self->config->{type} eq 'edit' ? {
            key => 'equipment_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),
         {
            key => 'equipment_room',
            label => trm('Room'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
                required => true,
            },
        },
        {
            key => 'equipment_key',
            label => trm('Key'),
            widget => 'text',
            set => {
                required => true,
            },
        },
        {
            key => 'equipment_name',
            label => trm('Name'),
            widget => 'text',
            set => {
                required => true,
            },
        },
        {
            key => 'equipment_start_ts',
            label => trm('Available From'),
            widget => 'date',
            set => {
                maxWidth => 100,
                required => true,
            },
        },{
            key => 'equipment_end_ts',
            label => trm('Last Day'),
            widget => 'date',
            set => {
                maxWidth => 100,
                required => true,
            },
        },
        {
            key => 'equipment_cost',
            label => trm('Cost'),
            widget => 'text',
            set => {
                required => true,
            },
        },
    ];
};

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = sub {
        my $self = shift;
        my $args = shift;
        $self->args->{selection}{review_id} = $args->{review_id};
        my %metaInfo;
        my $data = {
                map { 'equipment_'.$_ => $args->{'equipment_'.$_} } qw(
                    room name key cost start_ts end_ts
                )
            };
        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('equipment',$data)
                ->last_insert_id;
        }
        else {
            $self->db->update('equipment',$data ,{
                 equipment_id => $args->{equipment_id}});
        }
        return {
            action => 'dataSaved',
            metaInfo => \%metaInfo
        };
    };

    return [
        {
            label => $type eq 'edit'
               ? trm('Save Changes')
               : trm('Add Equipment'),
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
    if ($self->config->{type} eq 'add') {
        my $room = $args->{selection}{room_id};
        if ($room) {
            return {
                equipment_room => $room
            };
        }
        die mkerror(3938,trm("no selection->room_id found"));
    }
    if (my $id = $args->{selection}{equipment_id}){
        my $db = $self->db;
        my $data = $db->select('equipment','*',
            ,{equipment_id => $id})->hash;
        return $data;
    }
    die mkerror(3938,trm("no selection found"));
}


1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
