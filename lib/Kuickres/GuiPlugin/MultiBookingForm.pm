package Kuickres::GuiPlugin::MultiBookingForm;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false to_json);
use Time::Piece qw(localtime);
use Mojo::Util qw(dumper);
use DBI qw(:sql_types);
use Role::Tiny::With;
with 'Kuickres::Role::JsonField';
with 'Kuickres::Role::BookingHelper';

use POSIX qw(strftime);

=head1 NAME

Kuickres::GuiPlugin::MultiBookingForm - MultiBooking Editor Edit Form

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::MultiBookingForm;

=head1 DESCRIPTION

Edit MultiBooking

=cut

has checkAccess => sub ($self) {
    return $self->user->may('admin');
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

# as this code uses transactions, it is important to use the same db handle
has db => sub ($self){
    return $self->user->mojoSqlDb;
};

has mailer => sub ($self) {
    Kuickres::Model::Email->new( app=> $self->app, log=>$self->log );
};

=head2 formCfg

Returns a Configuration Structure for the Location Entry Form.

=cut

has sample_rule => sub ($self) {
    my $rule = <<'SAMPLE_RULE';
bestEffort: false
user: kuickres@login.name
mobile: mobile_number
SAMPLE_RULE
    $self->db->select('district','*',undef,{order_by => 'district_id'})->hashes->map(sub {
        $rule .= "#districtId: $_->{district_id} # $_->{district_name}\n"
    });
    $self->db->select('agegroup','*',undef,{order_by => 'agegroup_id'})->hashes->map(sub {
        $rule .= "#agegroupId: $_->{agegroup_id} # $_->{agegroup_name}\n"
    });
    $rule .= <<'SAMPLE_RULE';
school: school_house
equipmentList:
SAMPLE_RULE
    for (@{$self->eqList}) {
        $rule .= "# - $_\n"
    }
    $rule .= <<'SAMPLE_RULE';
interval: weekly
#interval: biweekly
day:
# - mon
# - tue
# - wed
# - thu
# - fri
startTime: 15:00
endTime: 17:00
SAMPLE_RULE
    return $rule;
};

has eqList => sub ($self) {
    $self->db->select('equipment','equipment_key')->hashes->map(sub {
        $_->{equipment_key}
    })->to_array;
};

has ruleValidator => sub ($self) {
    my $eqList = $self->eqList;
    my $weekDays = [qw(mon tue wed thu fri sat sun)];
    my $validator = $self->formFieldValidatorFactory({
        '$schema' =>  "http://json-schema.org/draft-07/schema",
        '$defs' => {
            tod24Spec => {
                type => 'string',
                pattern => '^\d\d?:\d\d$'
            },
        },
        type =>  "object",
        additionalProperties => false,
        required => [qw(
            bestEffort
            equipmentList
            interval
            day
            startTime
            endTime
            mobile
            agegroupId
            districtId
            school
        )],
        properties =>  {
            bestEffort => {
                type => 'boolean'
            },
            user => {
                type => 'string',
                pattern => '^[^\s@]+@[^\s@]+$',
            },
            agegroupId => {
                type => 'integer',
            },
            districtId => {
                type => 'integer',
            },
            school => {
                type => 'string'
            },
            mobile => {
                type => 'string',
                pattern => '^07\d(?:\s*\d\s*){7}$'
            },
            
            equipmentList => {
                type => 'array',
                items => {
                    enum => $eqList
                },
                minItems => 1,
                uniqueItems => true,
                additionalItems => false
            },
            interval => {
                enum => [qw(weekly biweekly)]
            },
            day => {
                oneOf => [
                    {
                        enum => $weekDays
                    },
                    {
                        type => 'array',
                        additionalItems => false,
                        items => {
                            enum => $weekDays
                        },
                        uniqueItems => true,
                        additionalItems => false,
                    }
                ]
            },
            startTime => {
                '$ref' => '#/$defs/tod24Spec'
            },
            endTime => {
                '$ref' => '#/$defs/tod24Spec'
            },
        }
    });
    return sub ($rule,$field,$form) {
        my $return = $validator->($rule,$field,$form);
        return $return if $return;
        $self->db->select('agegroup','*',{
            agegroup_id => $rule->{agegroupId}
        })->hash or return "Unknown agegroupId!";
        $self->db->select('district','*',{
            district_id => $rule->{districtId}
        })->hash or return "Unknown districtId!";
        $self->db->select('cbuser','*',{
            cbuser_login => $rule->{user}
        })->hash or return "Unknown user!";
        $_[0] = $rule;
        return;
    }
};


has formCfg => sub ($self) {
    my $db = $self->db;
    
    return [
        $self->config->{type} eq 'edit' ? {
            key => 'mbooking_id',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        } : (),
        {
            key => 'mbooking_room',
            label => trm('Id'),
            widget => 'hiddenText',
            set => {
                readOnly => true,
            },
        },
        {
            key => 'mbooking_start_ts',
            label => trm('Start Date'),
            widget => 'date',
            set => {
                maxWidth => 100,
                required => true,
            },
            validator => sub ($value,$fieldName,$form) {
                return trm("Must be a number")
                    if $value !~ /^\d+$/;
                return;
            }
        },{
            key => 'mbooking_end_ts',
            label => trm('End Date'),
            widget => 'date',
            set => {
                maxWidth => 100,
                required => true,
            },
            validator => sub ($value,$fieldName,$form) {
                return trm("Must be a number")
                    if $value !~ /^\d+$/;
                
                return trm("End Data must be after the Start Date")
                    if $value <= $form->{mbooking_start_ts};
                return;
            }
        },
        {
            key => 'mbooking_rule',
            label => trm('Rule'),
            widget => 'textArea',
            set => {
                height => 400,
                required => true,
                placeholder => $self->sample_rule
            },
            validator => $self->ruleValidator,
        },
        {
            key => 'mbooking_note',
            label => trm('Note'),
            widget => 'textArea',
        },
    ];
};

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = sub {
        my $self = shift;
        my $args = shift;
        $self->log->debug(dumper \@_);
        my %metaInfo;
        my $db = $self->db;
        my $tx = $db->begin;
        $args->{mbooking_rule_json} = to_json($args->{mbooking_rule});
        $args->{mbooking_cbuser} = $self->user->userId;
        if ($type eq 'add')  {
            $args->{mbooking_create_ts} = time;
            $args->{mbooking_id} = $metaInfo{recId} = $db->insert('mbooking',{
                map { "mbooking_".$_ => $args->{"mbooking_".$_} } qw(
                    room cbuser start_ts end_ts rule_json note create_ts
                )
            })->last_insert_id;
        }
        else {
            $db->update('mbooking', {
                map { 'mbooking_'.$_ => $args->{'mbooking_'.$_} } qw(
                    cbuser start_ts end_ts rule_json note 
                )
            },{ mbooking_id => $args->{mbooking_id}});

            $db->update('booking',{
                booking_delete_ts => time,
            },{
                booking_mbooking => $args->{mbooking_id},
                booking_delete_ts => undef,
                booking_start_ts => { '>' => time }
            });
        }
        my ($success,$problems) = $self->multiBook(
            $args->{mbooking_id},
            $args->{mbooking_room},
            $args->{mbooking_start_ts},
            $args->{mbooking_end_ts}+24*3600,
            $args->{mbooking_rule}
        );

        my $message;
        my $good = "Die folgenden Reservationen konnte erzeugt werden: <ul>".join("\n",map {"<li>$_</li>"} @$success)."</ul>";
        my $bad = "Die folgenden Reservationen konnten nicht erzeugt werden: <ul>";

        for my $prob (@$problems) {
            next unless $prob; #skip silent problems
            $bad .= "<li>$prob->{key}<ul>"
            . join("\n",map {"<li>Überlappend $_</li>"} @{$prob->{overlaps}})
            . join("\n",map {"<li>$_</li>"} @{$prob->{issues}})
            ."</ul></li>";
        }
        $bad .= "</ul>";

        if (@$success) {
            if (not @$problems) {
                $message = $good;        
            }
            elsif ($args->{mbooking_rule}{bestEffort}) {
                $message = $good."<br/>".$bad;
            }
            else {
                return {
                    action => 'showMessage',
                    html => true,
                    message => "Keine Reservationen wurden erzeugt. ".$bad."<div>Wenn Du das <b>bestEffort</b> Flag auf 'true' setzt, dann könnten folgende Reservationen erzeugt werden: <ul>".join("\n",map {"<li>$_</li>"} @$success)."</ul>",
                    title => "Probleme",
                }
            }
        }
        else {
            return {
                action => 'showMessage',
                html => true,
                title => "Probleme",
                width => '600',
                message => "Keine Reservationen wurden erzeugt. ".$bad
            };
        }
        my $rule = $args->{mbooking_rule};
        my $user = $db->select('cbuser','*',{
            cbuser_login => $rule->{user}
        })->hash;
        my $room = $db->select(['room',
            [ 'location', 'location_id' => 'room_location']],'*',{
            room_id => $args->{mbooking_room}
        })->hash;

        my @eqListLong;
        $db->select('equipment', '*', { 
            equipment_key => { in => $rule->{equipmentList} } }
        )->hashes->map(sub ($rec) {
            push @eqListLong, $rec->{equipment_name};
        });

        $self->mailer->sendMail({
            to => $user->{cbuser_login},
            template => 'mbooking',
            args => {
                id => $args->{mbooking_id},
                date => localtime->strftime(trm('%d.%m.%Y')),
                location => $room->{location_name} . ' - ' . $room->{location_address},
                equipmentList => \@eqListLong,
                room => $room->{room_name},
                accesscode => $user->{cbuser_pin},
                email => $user->{cbuser_login},
                message => $message,
            }
        });
        $tx->commit;

        return {
            action => 'dataSaved',
            title => 'Status',
            message => $message,
            html => true,
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
        my $room = $args->{selection}{room_id};
        if ($room) {
            return {
                mbooking_room => $room,
                mbooking_rule => $self->sample_rule
            };
        }
        die mkerror(3938,trm("no selection->room_id found"));
    }
    if (my $id = $args->{selection}{mbooking_id}){
        my $db = $self->db;
        my $data = $db->select('mbooking','*',
            ,{mbooking_id => $id})->hash;
        $data->{mbooking_rule} = 
            $self->toYaml(delete $data->{mbooking_rule_json});
        return $data;

    }
    die mkerror(3938,trm("no selection found"));
}

my %dayMap = (
    sun => 0,
    mon => 1,
    tue => 2,
    wed => 3,
    thu => 4,
    fri => 5,
    sat => 6
);

sub multiBook ($self,$recId,$room,$start,$end,$rule) {
    my $db = $self->db;
    my $date = '%Y-%m-%d';
    $end = localtime($end)->truncate(to => 'day');
    my $now = $start = localtime($start)->truncate(to => 'day');

    my $user = $db->select('cbuser','*',{
        cbuser_login => $rule->{user}
    })->hash;
    #$self->log->debug(dumper $rule);
    die mkerror(3949,trm("unknown user configured in rule")) unless $user;
    
    $user = $user->{cbuser_id};

    my $week_start = $start;

    my @equipment;
    $db->select('equipment','equipment_id',{
        equipment_key => $rule->{equipmentList}
    })->hashes->map(sub ($rec) {
        push @equipment, $rec->{equipment_id};
    });

    my $startTime = $self->timeToSec($rule->{startTime});
    my $endTime = $self->timeToSec($rule->{endTime});
    my $duration = $endTime-$startTime;
    
    my $dayFilter = { 
        map {
            $dayMap{$_} => true
        } ref $rule->{day} eq 'ARRAY' 
        ? (@{$rule->{day}}) : $rule->{day} 
    };
    my @problem;
    my @success;
    while ($now->epoch < $end->epoch){
        if ($dayFilter->{$now->day_of_week}) {
            my @currentEq = @equipment;
            #$self->log->debug("working on ".$now->strftime);
            my @conflict;
            my $start = $now+$startTime;
            my $end = $now+$endTime;
            my $key = $start->strftime("%a, %d.%m.%Y %H:%M")." - "
                . $end->strftime("%H:%M");

            my @args = (
                $user,
                $start->epoch,
                $end->epoch,
                $room,
                \@currentEq
            );
            #$self->log->debug("FULL ", dumper \@args);
            my $overlaps = $self->getBookings(@args);
            my @overlapEq;
            if ($overlaps) {
                @overlapEq = map { ($overlaps->{eq_hash}{$_} or exists $overlaps->{eq_hash}{0})
                    ? ($overlaps->{eq_hash}{$_}) : () } @equipment;

                @currentEq = grep {not $overlaps->{eq_hash}{$_} } @equipment;

                if (@currentEq) {
                    #$self->log->debug("CLEAN " ,dumper \@args,\@currentEq,$overlaps);
                    if ($self->getBookings(@args)){
                        die mkerror(8474,trm("Internal error with eq removal"));
                    }
                    # we can book some equipment it seems
                    $overlaps = undef;
                };   
            }
            my $issues = $self->checkResourceAllocations(@args);

            if (not $overlaps and not $issues) {
                my $id = $db->insert('booking',{
                    booking_mbooking => $recId,
                    booking_start_ts => $start->epoch,
                    booking_duration_s => $duration,
                    booking_create_ts => time,
                    booking_cbuser => $user,
                    booking_room => $room,
                    booking_mobile => $rule->{mobile},
                    booking_agegroup => $rule->{agegroupId},
                    booking_district => $rule->{districtId},
                    booking_school => $rule->{school},
                    booking_equipment_json => to_json(\@currentEq),
                })->last_insert_id;
                push @success, "$id - $key"
                . (@overlapEq ? " ".trm("(Ohne: %1!)",join(', ',@overlapEq)) : '');
                if(@overlapEq) {
                    push @problem, ''; # a silent problem marker
                };
            }
            else {
                push @problem, {
                    key => $key,
                    overlaps => $overlaps->{desc_array},
                    issues => $issues,
                };
            }
        }
        $now = ($now+36*3600)->truncate(to => 'day');
        if ($rule->{interval} eq 'biweekly' 
            and ($now-$week_start)->days >=7) {
            $week_start = $now = ($now + 6*24*3600 + 36*3600)->truncate(to => 'day');
        }

    }
    return \@success,\@problem;
}
1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-02-21 oetiker 0.0 first version

=cut
