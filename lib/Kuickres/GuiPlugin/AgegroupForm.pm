package Kuickres::GuiPlugin::AgegroupForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::AgegroupForm - Song Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::AgegroupForm;

=head1 DESCRIPTION

The Agegroup Edit Form

=cut

has checkAccess => sub {
    my $self = shift;
        return 0 if $self->user->userId eq '__ROOT';

    return $self->user->may('admin');
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Agegroup Entry Form.

=cut



has formCfg => sub {
    my $self = shift;
    my $db = $self->user->db;

    return [
        $self->config->{type} eq 'edit' ? {
            key => 'agegroup_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),

        {
            key => 'agegroup_name',
            label => trm('Name'),
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
        my %metaInfo;
        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('agegroup',{
                map { "agegroup_".$_ => $args->{"agegroup_".$_} } qw(
                    name
                )
            })->last_insert_id;
        }
        else {
            $self->db->update('agegroup', {
                map { 'agegroup_'.$_ => $args->{'agegroup_'.$_} } qw(
                    name
                )
            },{ agegroup_id => $args->{agegroup_id}});
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
               : trm('Add Agegroup'),
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
    my $data = $db->select('agegroup','*'
        ,{agegroup_id => $id})->hash;
    return $data;
}

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
