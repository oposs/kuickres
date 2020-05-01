package Kuickres::GuiPlugin::LocationForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm';
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);

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
            key => 'location_open',
            label => trm('Opening Time'),
            required => true,
            set => {
                placeholder => 'HH:MM'
            },
            widget => 'text',
            validator => sub {
                my $value = shift;
                if ($value !~ /^\d{2}:\d{2}$/) {
                    return trm("Expected HH:MM");
                }
                return;
            }
        },
        {
            key => 'location_close',
            label => trm('Closing Time'),
            required => true,
            set => {
                placeholder => 'HH:MM'
            },
            widget => 'text',
            validator => sub {
                my $value = shift;
                my $fieldName = shift;
                my $form = shift;
                if ($value !~ /^\d{2}:\d{2}$/) {
                    return trm("Expected HH:MM");
                }
                return;
            }
        },
        {
            key => 'location_address',
            label => trm('Address'),
            widget => 'textArea',
            set => {
                placeholder => "Street Nr\nPLZ Ort"
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
        my $start = $args->{location_open};
        $start =~ s/(\d+):(\d+)/$1*3600+$2*60/e;
        my $end = $args->{location_close};
        $end =~ s/(\d+):(\d+)/$1*3600+$2*60/e;
        if ($end < $start) {
            $end += 3600*24;
        }
        $args->{location_open_start} = $start;
        $args->{location_open_duration} = $end - $start;

        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('location',{
                map { "location_".$_ => $args->{"location_".$_} } qw(
                    name address open_start open_duration
                )
            })->last_insert_id;
        }
        else {
            $self->db->update('location', {
                map { 'location_'.$_ => $args->{'location_'.$_} } qw(
                    name address open_start open_duration
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
    my $data = $db->select('location',['*',
        \"strftime('%H:%M',location_open_start,'unixepoch') AS location_open",
        \"strftime('%H:%M',location_open_start+location_open_duration,'unixepoch') AS location_close"]
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
