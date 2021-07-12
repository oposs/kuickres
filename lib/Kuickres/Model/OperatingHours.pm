package Kuickres::Model::OperatingHours;
use Mojo::Base -base,-signatures;
use JSON::Validator;
use Mojo::JSON qw(decode_json false true);
use Mojo::Exception;
use Mojo::Util qw(dumper);
use YAML::XS qw(Load);
use Time::Piece;

has 'rules';

has jv => sub {
    my $jv = JSON::Validator->new(version=>7);
    # Define a schema - http://json-schema.org/learn/miscellaneous-examples.html
    # You can also load schema from disk or web
    $jv->formats->{simpletime} = sub { 
        return defined $_[0] && $_[0] =~ /^(\d{1,2}:\d{2}|\d+(?:\.\d+)?)$/ 
        ? undef 
        : "Invalid time format. Expected hh:mm or h.dd"
    };
    $jv->schema('data:///hours.yaml');
    return $jv;
};

sub new  {
    my $class = shift;
    my $self = $class->SUPER::new;
    my $rules = shift;
    local $@;
    $self->rules(ref $rules eq 'ARRAY' ? $rules : eval { Load($rules) });
    if ($@){
        Mojo::Exception->throw($@);
    }
    # warn dumper $self->rules;
    my @errors = $self->jv->validate($self->rules);
    if (@errors){
        Mojo::Exception->throw(join "\n", map { $_->to_string } @errors);
    }
    for my $rule (@{$self->rules}){
        my $tr = $rule->{time};
        for my $type (qw(from to)) {
            $tr->{$type} = $self->_strToTime($tr->{$type});
        }
    }
    return $self;
};

sub _strToTime ($self,$in) {
    return unless defined $in;
    for ($in) {
        /^(\d{1,2}(?:\d+)?)$/ && do {
            return int($1*3600);
        };
        /^(\d{1,2}):(\d{2})$/ && do {
            return $1*3600+$2*60;
        };
        Mojo::Exception->throw('Invalid time format');
    }
    return;
}

sub _parseTime ($self,$in) {
    if (ref $in ne 'Time::Piece'){
        for ($in) {
            /^\d+$/ && do {
                $in = localtime($in);
                last;
            };
            /^\d{1,2}\.\d{1,2}\.\d{4} \d{1,2}:\d{2}$/ && do {
                $in = localtime->strptime($in,'%d.%m.%Y %H:%M');
                last;    
            };
            Mojo::Exception->throw('Invalid time format');
        }
        return {
            day => lc($in->day),
            time => $in->hour * 3600 + $in->min * 60 + $in->sec,
        }
    }
}

=head2 isItOpen($from,$to)

$from and $to can be either 

=cut

sub isItOpen ($self,$from,$to) {
    $from = $self->_parseTime($from);
    $to = $self->_parseTime($to);
    return false if $from->{time} > $to->{time};
    for my $rule (@{$self->rules}){
        my $dr = $rule->{day};
        my $tr = $rule->{time};
        for my $day ( ref $dr eq 'ARRAY' ? @$dr : $dr) {
            for my $time ( ref $tr eq 'ARRAY' ? @$tr : $tr) {
                next unless 
                    $from->{day} eq $to->{day} 
                    and $to->{day} eq $day;
                
                if ($rule->{type} eq 'open') {
                    return true if
                        $from->{time} >= $time->{from}
                        and $to->{time} <= $time->{to};
                }
                else {
                    return false
                     if $from->{time} < $time->{to}
                        and $to->{time} > $time->{from};
                }
            }
        }
    }
    return false;
}

=head2 getOpeningTimes (start,end,step)

returns
 
 {
     hours => [[ start, end],[start, end]],
     times => [ts1,ts2,ts3]
 }

=cut

sub getOpeningTimes ($self,$from,$to,$step=300) {
    $from = $self->_parseTime($from);
    $to = $self->_parseTime($to);
    my @hours;
    my @times;
    my $start;
    my $end;
    for (my $time = $from;$time < $to;$time += $step) {
        if ($self->isItOpen($time,$to)){
            push @times,$time;
            $start //= $time;
            $end = $to;
        }
        elsif ($start) {
            push @hours, [$start,$end];
            $start = undef;
        }
    }
    if ($start) {
            push @hours, [$start,$end];
    }
    return {
        hours => \@hours,
        times => \@times
    };
}

1;
__DATA__

@@ hours.yaml
$id: https://kuickres.org/hours.yaml
$schema: http://json-schema.org/draft-07/schema#
definitions:
    weekday:
        type: string
        enum:
            - mon
            - tue
            - wed
            - thu
            - fri
            - sat
            - sun
    timerange:
        type: object
        additionalProperties: false
        required:
            - from
            - to
        properties:
            from:
                type: string
                format: simpletime
            to:
                type: string
                format: simpletime
type: array
items:
    type: object
    additionalProperties: false
    required:
        - type
        - day
        - time
    properties:
        type:
            type: string
            enum:
                - open
                - close
        day:
            oneOf:
                - type: array
                  items:
                    $ref: '#/definitions/weekday'
                - $ref: '#/definitions/weekday'
        time:
            oneOf:
                - type: array
                  items:
                    $ref: '#/definitions/timerange'
                - $ref: '#/definitions/timerange'
