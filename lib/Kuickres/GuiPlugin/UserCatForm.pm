package Kuickres::GuiPlugin::UserCatForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Role::Tiny::With;
with 'Kuickres::Role::JsonField';

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::RoomForm - UserCat Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::UserCatForm;

=head1 DESCRIPTION

The Location Edit Form

=cut

has checkAccess => sub {
    my $self = shift;
    return $self->user->may('admin');
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    return shift->user->mojoSqlDb;
}


=head2 formCfg

Returns a Configuration Structure for the Location Entry Form.

=cut

has sample_rule => sub ($self) {
    my $rule = <<'SAMPLE_RULE';
futureBookingDays: 60
maxEquipmentPointsPerBooking: 5
maxBookingHoursPerDay: 4
allowDoubleBooking: false
equipmentList:
SAMPLE_RULE
    for (@{$self->eqList}) {
        $rule .= "  - $_\n"
    }
    return $rule;
};

has eqList => sub ($self) {
    $self->db->select('equipment','equipment_key')->hashes->map(sub {
        $_->{equipment_key}
    })->to_array;
};

has formCfg => sub {
    my $self = shift;
    my $db = $self->db;
    my $eqList = $self->eqList;
    return [
        $self->config->{type} eq 'edit' ? {
            key => 'usercat_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),
        {
            key => 'usercat_name',
            label => trm('Name'),
            widget => 'text',
            required => true,
            set => {
                required => true,
            },
        },
        {
            key => 'usercat_rule',
            label => trm('Rule'),
            widget => 'textArea',
            set => {
                height => 300,
                required => true,
                placeholder => $self->sample_rule
            },
            validator => $self->formFieldValidatorFactory({
                '$schema' =>  "http://json-schema.org/draft-07/schema",
                type =>  "object",
                additionalProperties => false,
                required => [qw(
                    futureBookingDays
                    maxEquipmentPointsPerBooking
                    maxBookingHoursPerDay
                    equipmentList
                )],
                properties =>  {
                    futureBookingDays => {
                        type => 'number',
                        decription => 'Number of days in the future booking is allowed'
                    },
                    maxEquipmentPointsPerBooking => {
                        type => 'number',
                        decription => 'How many equipment points can be spent per booking'
                    },
                    maxBookingHoursPerDay => {
                        type => 'number',
                        description => 'How many hours per day are allowed in a booking'
                    },
                    equipmentList => {
                        type => 'array',
                        items => {
                            enum => $eqList
                        },
                        minItems => 1,
                        uniqueItems => true,
                        additionalItems => false,
                    },
                    allowDoubleBooking => {
                        type => 'boolean',
                        description => 'Allow double booking',
                        default => false,
                    },
                }
            })
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
        $args->{usercat_rule_json} = to_json($args->{usercat_rule});
        if ($type eq 'add')  {
            $metaInfo{recId} = $self->db->insert('usercat',{
                map { "usercat_".$_ => $args->{"usercat_".$_} } qw(
                    name rule_json
                )
            })->last_insert_id;
        }
        else {
            $self->db->update('usercat', {
                map { 'usercat_'.$_ => $args->{'usercat_'.$_} } qw(
                    name rule_json
                )
            },{ usercat_id => $args->{usercat_id}});
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
               : trm('Add UserCat'),
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
    if ($self->config->{type} eq 'add') {
       return {
           usercat_rule => $self->sample_rule
      };
    }
    if (my $id = $args->{selection}{usercat_id}){
        my $db = $self->db;
        my $data = $db->select('usercat','*',
            ,{usercat_id => $id})->hash;
        $data->{usercat_rule} = $self->toYaml(delete $data->{usercat_rule_json});
        return $data;

    }
    die mkerror(3938,trm("no selection found"));
}


1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
