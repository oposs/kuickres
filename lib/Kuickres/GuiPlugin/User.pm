package Kuickres::GuiPlugin::User;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractTable';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

=head1 NAME

CallBackery::GuiPlugin::Users - User Plugin

=head1 SYNOPSIS

 use CallBackery::GuiPlugin::Users;

=head1 DESCRIPTION

The User Plugin.

=cut


=head1 PROPERTIES

All the methods of L<CallBackery::GuiPlugin::AbstractTable> plus:

=cut

=head2 tableCfg


=cut

sub db {
    return shift->user->mojoSqlDb;
};

has tableCfg => sub {
    my $self = shift;
    my $admin = ( not $self->user or $self->user->may('admin'));
    
    return [
        {
            label => trm('UserId'),
            type => 'number',
            width => '1*',
            key => 'cbuser_id',
            sortable => true,
            primary => true,
        },
        {
            label => trm('Username'),
            type => 'string',
            width => '3*',
            key => 'cbuser_login',
            sortable => true,
        },
        {
            label => trm('Given Name'),
            type => 'string',
            width => '4*',
            key => 'cbuser_given',
            sortable => true,
        },
        {
            label => trm('Family Name'),
            type => 'string',
            width => '4*',
            key => 'cbuser_family',
            sortable => true,
        },
        {
            label => trm('User Category'),
            type => 'string',
            width => '4*',
            key => 'usercat_name',
            sortable => true,
        },
        {
            label => trm('Rights'),
            type => 'string',
            sortable => false,
            width => '8*',
            key => 'cbuser_cbrights',
        },
        $admin ? ({
            label => trm('Note'),
            type => 'string',
            width => '8*',
            key => 'cbuser_note',
        }):(),
     ]
};

=head2 actionCfg

=cut

has actionCfg => sub {
    my $self = shift;
    # we must be in admin mode if no user property is set to have be able to prototype all forms variants
    my $admin = ( not $self->user or $self->user->may('admin'));
    return [
        $admin ? ({
            label => trm('Add User'),
            action => 'popup',
            addToContextMenu => true,
            name => 'userFormAdd',
            popupTitle => trm('New User'),
            set => {
                height => 500,
                width => 500
            },
            backend => {
                plugin => 'UserForm',
                config => {
                    type => 'add'
                }
            }
        }) : (),
        {
            label => trm('Edit User'),
            action => 'popup',
            buttonSet => {
                enabled => false
            },
            addToContextMenu => true,
            defaultAction => true,
            name => 'userFormEdit',
            key => 'edit',
            popupTitle => trm('Edit User'),
            actionHandler => sub {
                my $self = shift;
                my $args = shift;
                my $id = $args->{selection}{cbuser_id};
                die mkerror(393,trm('You have to select a user first'))
                    if not $id;
            },
            set => {
                height => 500,
                width => 500
            },
            backend => {
                plugin => 'UserForm',
                config => {
                    type => 'edit'
                }
            }
        },
        $admin ? ({
            label => trm('Delete User'),
            action => 'submitVerify',
            addToContextMenu => true,
            question => trm('Do you really want to delete the selected user ?'),
            key => 'delete',
            buttonSet => {
                enabled => false
            },
            actionHandler => sub {
                my $self = shift;
                my $args = shift;                
                my $id = $args->{selection}{cbuser_id};
                die mkerror(4992,trm("You have to select a user first"))
                    if not $id;
                die mkerror(4993,trm("You can not delete the user you are logged in with"))
                    if $id == $self->user->userId;
                my $db = $self->user->db;

                if ($db->deleteData('cbuser',$id) == 1){
                    return {
                         action => 'reload',
                    };
                }
                die mkerror(4993,trm("Faild to remove user %1",$id));
            }
        }) : (),
    ];
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut


sub currentUserFilter {
    my $self = shift;
    if (not $self->user->may('admin')){
        return 'WHERE cbuser_id = ' . $self->user->mojoSqlDb->dbh->quote($self->user->userId);
    }
    return '';
}

sub getTableRowCount {
    my $self = shift;
    my $args = shift;
    my $db = $self->db;
    if ($self->user->may('admin')){
        return $db->select('cbuser','count(cbuser_id) AS c')->hash->{c};
    }
    return 1;
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
    my $data = $db->select(['cbuser', [ -left => 'usercat', usercat_id => 'cbuser_usercat']],'*',
        ! $self->user->may('admin') ? {
            cbuser_id => $self->user->userId,
        } : undef,
        {
            %SORT,
            limit => $args->{lastRow}-$args->{firstRow}+1,
            offset => $args->{firstRow}
        })->hashes;

    my @users = map { $_->{cbuser_id} } @$data;
    my %rights;
    $db->select(['cbuserright',['cbright','cbright_id' => 'cbuserright_cbright']],'*',{
        cbuserright_cbuser => { -in => \@users }
    } )->hashes->map(sub {
        push @{$rights{$_->{cbuserright_cbuser}}},$_->{cbright_label};
    });

    for my $row (@$data) {
        $row->{cbuser_cbrights} 
            = join ', ', sort @{$rights{$row->{cbuser_id}}}
                if ref $rights{$row->{cbuser_id}} eq 'ARRAY';
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

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=head1 COPYRIGHT

Copyright (c) 2014 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2013-12-16 to 1.0 first version

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4 et
