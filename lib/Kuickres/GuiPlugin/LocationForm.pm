package Kuickres::GuiPlugin::LocationForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Kuickres::Model::OperatingHours;

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::LocationForm - Song Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::LocationForm;

=head1 DESCRIPTION

The Location Edit Form

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

Returns a Configuration Structure for the Location Entry Form.

=cut



has formCfg => sub {
    my $self = shift;
    my $db = $self->user->db;

    return [
        $self->config->{type} eq 'edit' ? {
            key => 'location_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),

        {
            key => 'location_name',
            label => trm('Name'),
            widget => 'text',
            required => true,
            set => {
                required => true,
            },
        },
        {
            widget => 'header',
            label => trm('Location Details'),
            note => trm('Use the following fields to write down some extra information about the location.')
        },
        {
            key => 'location_open_yaml',
            label => trm('Operating Hours'),
            required => true,
            set => {
                height => 200,
                placeholder => <<OPENING_END,
- type: close
  day: mon
  time: { from: 12:00,to: 14:00 }
- type: open
  day:  [ 'mon','tue','wed','thu','fri']
  time:
    - { from: 8:00, to: 12:30 }
    - { from: 13:00, to: 18:30 }
OPENING_END
            },
            widget => 'textArea',
            validator => sub {
                my $value = shift;
                local $@;
                eval {
                    Kuickres::Model::OperatingHours->new($value);
                };
                return "$@";
            }
        },
        {
            key => 'location_address',
            label => trm('Address'),
            widget => 'text',
            set => {
                placeholder => "Street Nr, PLZ Ort"
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
        my %metaInfo;
        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('location',{
                map { "location_".$_ => $args->{"location_".$_} } qw(
                    name address open_yaml
                )
            })->last_insert_id;
        }
        else {
            $self->db->update('location', {
                map { 'location_'.$_ => $args->{'location_'.$_} } qw(
                    name address open_yaml
                )
            },{ location_id => $args->{location_id}});
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
               : trm('Add Location'),
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
    my $data = $db->select('location','*'
        ,{location_id => $id})->hash;
    return $data;
}


1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
