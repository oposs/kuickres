package Kuickres::GuiPlugin::MultiBooking;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Role::Tiny::With;

with 'Kuickres::Role::JsonField';

=head1 NAME

Kuickres::GuiPlugin::MultiBooking - MultiBooking List

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::MultiBooking;

=head1 DESCRIPTION

The Table Gui.

=cut

has checkAccess => sub {
    my $self = shift;
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
            key => 'mbooking_id',
            sortable => true,
            primary => true
        },
        {
            label => trm('Owner'),
            type => 'string',
            width => '1*',
            key => 'cbuser_login',
            sortable => true,
        },   
        {
            label => trm('Rule'),
            type => 'string',
            width => '1*',
            key => 'mbooking_rule_yaml',
            sortable => true,
        },
        {
            label => trm('Note'),
            type => 'string',
            width => '1*',
            key => 'mbooking_note',
            sortable => true,
        },
        {
            label => trm('Created'),
            type => 'date',
            format => trm('d.M.y'),
            width => '1*',
            key => 'mbooking_create_ts',
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
            label => trm('Edit MultiBooking'),
            action => 'popup',
            key => 'edit',
            addToContextMenu => false,
            popupTitle => trm('Edit MultiBooking'),
            buttonSet => {
                enabled => false
            },
            set => {
                height => 700,
                width => 500
            },
            backend => {
                plugin => 'MultiBookingForm',
                config => {
                    type => 'edit'
                }
            }
        },
        {
            label => trm('Delete MultiBooking'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the MultiBooking and all associated Bookings ?'),
            key => 'delete',
            buttonSet => {
                enabled => false
            },
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $id = $args->{selection}{mbooking_id};
                die mkerror(4992,"You have to select booking first")
                    if not $id;
                eval {
                    my $db = $self->db;
                    my $tx = $db->begin;
                    $db->update('booking',{
                        booking_delete_ts => time,
                    },{ -and => [
                        # only remove bookings from the future
                        -bool => [\['booking_start_ts > (? + 0)', time] ],
                        booking_mbooking => $id
                    ]});
                    $db->update('mbooking',{
                        mbooking_delete_ts => time,
                    },{
                        mbooking_id => $id
                    });
                    $tx->commit;
                };
                if ($@){
                    $self->log->error("remove MultiBooking $id: $@");
                    die mkerror(4993,"Failed to remove MultiBooking $id");
                }
                return {
                    action => 'reload',
                    message => trm("Alle zukuenftigen Bookings wurden aus der MultiBooking-Liste entfernt."),
                    title => trm('MultiBooking entfernt')
                };
            },
            backend => {
                plugin => 'MultiBookingForm',
                config => {
                    type => 'delete'
                }
            }
        },
    ];
};

sub db {
    return shift->user->mojoSqlDb;
}

sub getTableRowCount {
    my $self = shift;
    my $args = shift;
    return $self->db->select('mbooking','COUNT(*) AS count',{
        mbooking_delete_ts => undef 
    })->hash->{count};
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
    my $data = $db->select(['mbooking',[
        'cbuser','cbuser_id' => 'mbooking_cbuser']],'*',{
            mbooking_delete_ts => undef
        },
        {
            %SORT,
            limit => $args->{lastRow}-$args->{firstRow}+1,
            offset => $args->{firstRow}
        })->hashes->to_array;
    for my $row (@$data) {
        for my $key (keys %$row){
             next if $key !~ /_ts$/;
             $row->{$key} = $row->{$key} * 10**3 if $row->{$key};
        }
        $row->{mbooking_rule_yaml} = $self->toYaml(delete $row->{mbooking_rule_json});        
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
