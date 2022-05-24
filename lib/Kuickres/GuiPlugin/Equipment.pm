package Kuickres::GuiPlugin::Equipment;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

=head1 NAME

Kuickres::GuiPlugin::Equipment - Equipment Table

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::Equipment;

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
            key => 'equipment_id',
            sortable => true,
            primary => true
        },
        {
            label => trm('Key'),
            type => 'string',
            width => '1*',
            key => 'equipment_key',
            sortable => true,
        },
        {
            label => trm('Cost'),
            type => 'string',
            width => '1*',
            key => 'equipment_cost',
            sortable => true,
        }, 
         {
            label => trm('Start'),
            type => 'date',
            width => '1*',
            key => 'equipment_start_ts',
            sortable => true,
            format => trm('d.M.y'),
        },  {
            label => trm('End'),
            type => 'date',
            width => '1*',
            key => 'equipment_end_ts',
            sortable => true,
            format => trm('d.M.y'),
        }, 
        # {
        #     label => trm('Location'),
        #     type => 'string',
        #     width => '6*',
        #     key => 'location_name',
        #     sortable => true,
        # },
        {
            label => trm('Name'),
            type => 'string',
            width => '5*',
            key => 'equipment_name',
            sortable => true,
        },   
        {
             label => trm('Room'),
             type => 'string',
             width => '6*',
             key => 'room_name',
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
            label => trm('Edit Equipment'),
            action => 'popup',
            key => 'edit',
            addToContextMenu => false,
            popupTitle => trm('Edit Equipment'),
            buttonSet => {
                enabled => false
            },
            set => {
                minHeight => 500,
                minWidth => 500
            },
            backend => {
                plugin => 'EquipmentForm',
                config => {
                    type => 'edit'
                }
            }
        },
        {
            label => trm('Delete Equipment'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the selected Equipment?'),
            key => 'delete',
            buttonSet => {
                enabled => false
            },
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $id = $args->{selection}{room_id};
                die mkerror(4992,"You have to select equipment first")
                    if not $id;
                eval {
                    $self->db->delete('equipment',{equipment_id => $id});
                };
                if ($@){
                    $self->log->error("remove equipment $id: $@");
                    die mkerror(4993,"Failed to remove equipment $id");
                }
                return {
                    action => 'reload',
                };
            }
        }
    ];
};

sub db {
    return shift->user->mojoSqlDb;
};

sub getTableRowCount {
    my $self = shift;
    my $args = shift;
    return $self->db->select('equipment','COUNT(*) AS count')->hash->{count};
}

sub getTableData {
    my $self = shift;
    my $args = shift;
    my $db = $self->db;
    my %SORT; 
    if ( $args->{sortColumn} ){
        %SORT = (
            order_by => { 
                (
                    $args->{sortDesc} 
                    ? '-desc' 
                    : '-asc'
                ),
                $args->{sortColumn}
            }
        );
    }
    my $data = $db->select(['equipment', [ 
        'room', 'room_id' => 'equipment_room']],'*',undef,
        {
            %SORT,
            limit => $args->{lastRow}-$args->{firstRow}+1,
            offset => $args->{firstRow}
        })->hashes;
    for my $row (@$data) {
        for my $key (keys %$row){
             next if $key !~ /_ts$/;
             $row->{$key} = $row->{$key} * 10**3;
        }
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
