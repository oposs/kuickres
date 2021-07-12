package Kuickres::GuiPlugin::UserCat;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

=head1 NAME

Kuickres::GuiPlugin::UserCat - UserCat Table

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::UserCat;

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
            key => 'usercat_id',
            sortable => true,
            primary => true
        },
        {
            label => trm('Name'),
            type => 'string',
            width => '1*',
            key => 'usercat_name',
            sortable => true,
        },   
        {
            label => trm('Rules'),
            type => 'string',
            width => '1*',
            key => 'usercat_rules',
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
            label => trm('Add Category'),
            action => 'popup',
            addToContextMenu => false,
            name => 'UserCatForm',
            key => 'add',
            popupTitle => trm('New UserCat'),
            set => {
                height => 500,
                width => 500
            },
            backend => {
                plugin => 'UserCatForm',
                config => {
                    type => 'add'
                }
            }
        },
        {
            label => trm('Edit Category'),
            action => 'popup',
            key => 'edit',
            addToContextMenu => false,
            name => 'UserCatEditForm',
            popupTitle => trm('Edit UserCat'),
            buttonSet => {
                enabled => false
            },
            set => {
                height => 500,
                width => 500
            },
            backend => {
                plugin => 'UserCatForm',
                config => {
                    type => 'edit'
                }
            }
        },
        {
            label => trm('Delete Category'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the selected UserCat?'),
            key => 'delete',
            buttonSet => {
                enabled => false
            },
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $id = $args->{selection}{usercat_id};
                die mkerror(4992,"You have to select UserCat first")
                    if not $id;
                eval {
                    $self->db->delete('usercat',{usercat_id => $id});
                };
                if ($@){
                    $self->log->error("remove UserCat $id: $@");
                    die mkerror(4993,"Failed to remove UserCat $id");
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
    return $self->db->select('usercat','COUNT(*) AS count')->hash->{count};
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
    my $data = $db->select('usercat','*',undef,
        {
            %SORT,
            limit => $args->{lastRow}-$args->{firstRow}+1,
            offset => $args->{firstRow}
        })->hashes;
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
