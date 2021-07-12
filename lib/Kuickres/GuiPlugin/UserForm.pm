package Kuickres::GuiPlugin::UserForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::Util qw(hmac_sha1_sum dumper);
use Mojo::JSON qw(true false);

=head1 NAME

CallBackery::GuiPlugin::UserForm - UserForm Plugin

=head1 SYNOPSIS

 use CallBackery::GuiPlugin::UserForm;

=head1 DESCRIPTION

The UserForm Plugin.

=cut


=head1 PROPERTIES

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

=head2 formCfg

Returns a Configuration Structure for the Report Frontend Module.

=cut

my $DUMMY_PASSWORD = '>>NOt REALly a PaSSwoRd<<';

sub db {
    return shift->user->db;
};

has formCfg => sub {
    my $self = shift;
    
    if ($self->config->{type} eq 'edit' and not $self->args->{selection}{cbuser_id}){
        return [{
            label => trm('Error'),
            widget => 'header',
            note => trm('No user selected.')
        }];
    }
    my $usercat = $self->db->sql->db->select(
        'usercat',[
            \"usercat_id AS key",
            \"usercat_name AS title"
        ],undef,{ 
            order_by => ['usercat_name']
        }
    )->hashes->to_array;
    unshift @$usercat, {
        key => undef, title => trm("Select UserCat")
    };
    
    return [
        $self->config->{type} eq 'edit' ? {
            key => 'cbuser_id',
            label => trm('UserId'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),

        {
            key => 'cbuser_login',
            label => trm('Username'),
            widget => 'text',
            set => {
                required => true,
                readOnly => $self->user->may('admin') ? false : true
            },
        },
        {
            key => 'cbuser_password',
            label => trm('Password'),
            widget => 'password',
            set => {
                required => true,
            },
        },
        {
            key => 'cbuser_password_check',
            label => trm('Password Again'),
            widget => 'password',
            set => {
                required => true,
            },
        },

        {
            key => 'cbuser_given',
            label => trm('Given Name'),
            widget => 'text',
            set => {
                required => true,
                readOnly => $self->user->may('admin') ? false : true
            },
        },
        {
            key => 'cbuser_family',
            label => trm('Family Name'),
            widget => 'text',
            set => {
                required => true,
                readOnly => $self->user->may('admin') ? false : true
            }
        },
        
        $self->user->may('admin') ? (
        {
            key => 'cbuser_usercat',
            label => trm('User Category'),
            widget => 'selectBox',
            cfg => {
                structure => $usercat
            }
        },
        {
            key => 'cbuser_note',
            label => trm('Note'),
            widget => 'textArea',
            set => {
                placeholder => 'some extra information about this user',
            }
        } ) : (),
        @{$self->rightsCheckBoxes}
    ];
};

has rightsCheckBoxes => sub {
    my $self = shift;
    return [] if not $self->user->may('admin');
    my @checkboxes = {
        widget => 'header',
        label => 'Permissions'
    };
    my $db = $self->db->sql->db;
    my $rightTbl= $db->dbh->quote_identifier('cbright');
    my $rights = $db->select('cbright','*',{},{
        order_by => 'cbright_label'
    })->hashes->map(sub {
        push @checkboxes,
        {
            key => 'cbright_id_'.$_->{cbright_id},
            widget => 'checkBox',
            label => $_->{cbright_label},
        }
    });
    return \@checkboxes;
};


has actionCfg => sub {
    my $self = shift;
    my $mode = $self->config->{mode} // 'default';
    my $type = $self->config->{type} // 'new';

    my $handler = sub {
        my $self = shift;
        my $args = shift;
        my $admin = ($self->user->may('admin') or $mode eq 'init');

        my @fields = $admin ? (qw(login family given note usercat)) : ();
        my $itsMine = $args->{cbuser_id} == $self->user->userId;
        die mkerror(2847,trm("You can only edit your own stuff unless you have admin permissions."))
            unless $admin  or $itsMine;

        if ($args->{cbuser_password} ne $DUMMY_PASSWORD){
            die mkerror(2847,trm("The password instances did not match."))
                if $args->{cbuser_password} ne $args->{cbuser_password_check};
            push @fields, 'password';
        }

        $args->{cbuser_password} = hmac_sha1_sum($args->{cbuser_password});
        my $db = $self->db;

        $args->{cbuser_id} = $db->updateOrInsertData('cbuser',{
            map { $_ => $args->{'cbuser_'.$_} } @fields
        },$args->{cbuser_id} ? { id => int($args->{cbuser_id}) } : ());


        my $adminId = $db->fetchValue('cbright',{key=>'admin'},'id');
        if ($admin){
            for (keys %$args){
                next if not /^cbright_id_(\d+)$/;
                my $right_id = $1;
                my $match = {
                    cbuser => $args->{cbuser_id},
                    cbright => $right_id
                };
                # in init mode the user gets admin ... always
                if ($args->{$_}
                    or ( $mode eq 'init' and $right_id == $adminId )
                    or ( $itsMine and $right_id == $adminId )
                ){
                    $db->updateOrInsertData('cbuserright',$match,$match);
                }
                else {
                    $db->deleteDataWhere('cbuserright',$match);
                }
            }
        }

        if ($self->controller and $self->controller->can('runEventActions')){
            $self->controller->runEventActions('changeConfig');
        }
        return {
            action => $mode eq 'init' ? 'logout' : 'dataSaved'
        };
    };

    return [
        {
            label => $mode eq 'init'
               ? trm('Create Admin Account')
               : $type eq 'edit'
               ? trm('Save Changes')
               : trm('Add User'),
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
            _doc => "User Form Configuration",
            _vars => [ qw(type mode) ],
            type => {
                _doc => 'type of form to show: edit, add',
                _re => '(edit|add)'
            },
            mode => {
                _doc => 'In init mode the for will run for the __ROOT user and thus allow the creation of the initial account',
                _re => '(init|default)',
                _re_error => 'Pick one of init or default',
                _default => 'default'
            }
        },
    );
};

has checkAccess => sub {
    my $self = shift;
    my $userId = $self->user->userId;
    my $mode = $self->config->{mode} // 'default';
    if ($mode eq 'init'){
        return ($userId and $userId eq '__ROOT');
    }
    return $self->user;
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut


sub getAllFieldValues {
    my $self = shift;
    my $args = shift;
    return {} if $self->config->{type} ne 'edit';
    my $id = $args->{selection}{cbuser_id} // $self->user->userId;

    return {} unless $id;

    die mkerror(2847,"You can only edit your own stuff unless you have admin permissions.")
        if not ( $self->user->may('admin') or $id == $self->user->userId );

    my $db = $self->db;
    my $data = $db->sql->db->select(['cbuser', [-left => 'usercat', 'usercat_id' => 'cbuser_usercat']],'*',{
        cbuser_id => $id
    })->hash;
    $data->{cbuser_password} = $DUMMY_PASSWORD;
    $data->{cbuser_password_check} = $DUMMY_PASSWORD;

    my $rights = $db->sql->db->query(<<'SQL_END',$data->{cbuser_id})->hashes->to_array;
    SELECT * FROM
    cbright
    LEFT JOIN cbuserright ON 
        cbuserright_cbright = cbright_id
        AND 
        cbuserright_cbuser = ?
    ORDER BY
        cbright_label
SQL_END
    $self->log->debug(dumper $rights);
    for (@$rights){
        $data->{'cbright_id_'.$_->{cbright_id}} = $_->{cbuserright_cbuser} ? true : false;
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

Copyright (c) 2013 by OETIKER+PARTNER AG. All rights reserved.

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
