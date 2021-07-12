package Kuickres::Role::JsonField;
use Role::Tiny;
use Mojo::Base -base,-signatures;
use YAML::XS;
use JSON::Validator;
use Mojo::JSON qw(to_json from_json);
use Encode;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);

=head1 NAME

Kuickres::Role::JsonField - helpers for json fields

=head1 SYNOPSIS

 use Role::Tiny;
 with 'Kuickres::Role::JsonField';

=head1 DESCRIPTION

Helper Methods to deal with text fields storing structured data.

=cut

=head2 METHODS

=head3 formFieldValidatorFactory(schema)

create a validator, consuming yaml input, validating it using a json schema
and then replacing the field content with a json string

Example:

  $self->formFieldValidatorFactory({
    '$schema' =>  "http://json-schema.org/draft-07/schema",
    type =>  "object",
    additionalProperties =>  false,
    properties =>  {
        facebook => {
            type => 'string',
            pattern => '^\S+$' 
        },
        twitter => {
            type => 'string',
            pattern => '^\S+$' 
        },
    }
  })

=cut
use Carp;


sub formFieldValidatorFactory ($self,$jsonSchema) {  ## no critic (RequireArgUnpacking)
    my $validator = JSON::Validator->new;
    $validator->schema($jsonSchema);
    return sub ($value,$field,$form) {
        my $data = eval {
            local $SIG{__DIE__};
            Load(encode('utf-8',$value));
        };
        if ($@) {
            return trm("Invalid YAML Syntax: %1",$@);
        }
        if (my @errors = $validator->validate($data)){
            return join( "<br/>", @errors);
        }
        $_[0] = $data;  
        
        return;
    }
}


=head3 toYaml(json)

turn a json text string into a yaml text string

=cut

sub toYaml($self,$json) {
    my $yaml = decode('utf-8',Dump(from_json($json || '{}')));
    $yaml =~ s/^---(\s+{})?\n//;
    return $yaml;
}


1;