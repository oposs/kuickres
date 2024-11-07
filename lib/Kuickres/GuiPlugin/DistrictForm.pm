package Kuickres::GuiPlugin::DistrictForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::DistrictForm - Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::DistrictForm;

=head1 DESCRIPTION

The District Edit Form

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

Returns a Configuration Structure for the District Entry Form.

=cut



has formCfg => sub {
    my $self = shift;
    my $db = $self->user->db;

    return [
        $self->config->{type} eq 'edit' ? {
            key => 'district_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),

        {
            key => 'district_name',
            label => trm('District'),
            widget => 'text',
            set => {
                required => true,
            },
        },
        {
            key => 'district_active',
            label => trm('Aktiv'),
            widget => 'checkBox',
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
        $args->{district_active} = $args->{district_active} ? 1 : 0;
        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('district',{
                map { "district_".$_ => $args->{"district_".$_} } qw(
                    name active
                )
            })->last_insert_id;
        }
        else {
            $self->db->update('district', {
                map { 'district_'.$_ => $args->{'district_'.$_} } qw(
                    name active
                )
            },{ district_id => $args->{district_id}});
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
               : trm('Add District'),
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
    return {  district_active => true } if $self->config->{type} ne 'edit';
    my $id = $args->{selection}{district_id};
    return { } unless $id;

    my $db = $self->db;
    my $data = $db->select('district','*'
        ,{district_id => $id})->hash;
    $data->{district_active} = $data->{district_active} ? true : false;
    return $data;
}

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
