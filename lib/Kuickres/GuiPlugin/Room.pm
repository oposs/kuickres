package Kuickres::GuiPlugin::Room;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

=head1 NAME

Kuickres::GuiPlugin::Location - Room Table

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::Room;

=head1 DESCRIPTION

The Table Gui.

=cut

has checkAccess => sub {
    my $self = shift;
    return 0 if $self->user->userId eq '__ROOT';
    return $self->user->may('admin');
};


=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractTable> plus:

=cut

=head2 tableCfg


=cut

has tableCfg => sub {
    my $self = shift;
    return [
        {
            label => trm('Id'),
            type => 'number',
            width => '1*',
            key => 'room_id',
            sortable => true,
            primary => true
        },
        {
            label => trm('Name'),
            type => 'string',
            width => '6*',
            key => 'room_name',
            sortable => true,
        },
        {
            label => trm('Location'),
            type => 'string',
            width => '6*',
            key => 'location_name',
            sortable => true,
        },
     ]
};

=head2 actionCfg

Only users who can write get any actions presented.

=cut

has actionCfg => sub {
    my $self = shift;
    return [] if $self->user and not $self->user->may('admin');

    return [
        {
            label => trm('Add Room'),
            action => 'popup',
            addToContextMenu => false,
            name => 'RoomAddForm',
            key => 'add',
            popupTitle => trm('New Room'),
            set => {
                height => 500,
                width => 500
            },
            backend => {
                plugin => 'RoomForm',
                config => {
                    type => 'add'
                }
            }
        },
        {
            label => trm('Edit Room'),
            action => 'popup',
            key => 'edit',
            addToContextMenu => false,
            name => 'RoomEditForm',
            popupTitle => trm('Edit Room'),
            buttonSet => {
                enabled => false
            },
            set => {
                minHeight => 500,
                minWidth => 500
            },
            backend => {
                plugin => 'RoomForm',
                config => {
                    type => 'edit'
                }
            }
        },
        {
            label => trm('Delete Room'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the selected Room. This will only work if there are no reservations linked to it.'),
            key => 'delete',
            buttonSet => {
                enabled => false
            },
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $id = $args->{selection}{room_id};
                die mkerror(4992,"You have to select a room first")
                    if not $id;
                eval {
                    $self->db->delete('room',{room_id => $id});
                };
                if ($@){
                    $self->log->error("remove room $id: $@");
                    die mkerror(4993,"Failed to remove room $id");
                }
                return {
                    action => 'reload',
                };
            }
        }
    ];
};

sub db {
    shift->user->mojoSqlDb;
};

sub getTableRowCount {
    my $self = shift;
    my $args = shift;
    return $self->db->select('room','COUNT(*) AS count')->hash->{count};
}

sub getTableData {
    my $self = shift;
    my $args = shift;
    my $SORT = '';
    my $db = $self->db;
    my $dbh = $db->dbh;
    if ( $args->{sortColumn} ){
        $SORT = 'ORDER BY '.$dbh->quote_identifier($args->{sortColumn}).(
            $args->{sortDesc} 
            ? ' DESC' 
            : ' ASC' 
        );
    }
    my $data = $db->query(<<"SQL_END",
    SELECT * FROM room JOIN location ON room_location = location_id
    $SORT
    LIMIT ? OFFSET ?
SQL_END
       $args->{lastRow}-$args->{firstRow}+1,
       $args->{firstRow},
    )->hashes;
    for my $row (@$data) {
        $row->{_actionSet} = {
            edit => {
                enabled => true
            },
            delete => {
                enabled => true,
            },
        }
    }
    return $data;
}

1;

__END__

=head1 COPYRIGHT

Copyright (c) 2020 by Tobias Oetiker. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
