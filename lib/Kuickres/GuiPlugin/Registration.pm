package Kuickres::GuiPlugin::Registration;
use Mojo::Base 'Kuickres::GuiPlugin::ResetPassword', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Mojo::Util qw(dumper hmac_sha1_sum md5_sum);
use Time::Piece qw(localtime);
use POSIX qw(strftime);
use Email::MIME;
use Email::Sender::Simple;

=head1 NAME

Kuickres::GuiPlugin::Registration - Create a new Account

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::Registration;

=head1 DESCRIPTION

The Account Creation Form

=cut

=head1 METHODS

All the methods of L<Kuickres::GuiPlugin::ResetPassword> plus:

=cut

has accountMustExist => 0;

has createActionLabel => sub {
    trm('Create New Account');
};

has formCfg => sub ($self) {
    my $form = $self->SUPER::formCfg;
    my @new = (
        {
            key => 'given',
            label => trm('Given Name'),
            widget => 'text',
            set => {
                nativeContextMenu => true,
            },
        },
        {
            key => 'family',
            label => trm('Family Name'),
            widget => 'text',
            set => {
                nativeContextMenu => true,
            },
        },
    );
    splice(@$form,2,0,@new);
    return $form;
};

sub tokenMail ($self,$email,$token) {
    return trm('Hallo %1

Jemand versucht gerade ein neues Konto in Kuickres zu erstellen.
Falls sie das selber sind, tragen sie das untenstehende Token 
im Konto-Erzeugungs-Formular ein.

     %2


',$email,$token);
}

sub createAction ($self,$args) {
    # now all is required ... 
    for (qw(email token given family pass1 pass2)){
        die mkerror(3893,trm('%1 is required',ucfirst))
            unless $args->{$_};
    }
    eval {
        my $db = $self->db;
        my $tx = $db->begin;
        my $id = $db->insert('cbuser',{
            cbuser_password => hmac_sha1_sum($args->{pass1}),
            cbuser_login => $args->{email},
            cbuser_given => $args->{given},
            cbuser_family => $args->{family},
        })->last_insert_id;
        my $booker_id = $db->select('cbright','cbright_id',{
            cbright_key => 'booker'
        })->hash->{cbright_id};
        $db->insert('cbuserright',{
            cbuserright_cbuser => $id,
            cbuserright_cbright => $booker_id,
        });
        $tx->commit;
    };
    if ($@) {
        $self->log->error($@);
        die mkerror(3884,trm("Failed to create account for %1",$args->{email}));
    }
    return {
        action => 'dataSaved'
    };
}

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-03-16 oetiker 0.0 first version

=cut
