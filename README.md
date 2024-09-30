
Google API fucking sucks.

---

Set up your Google Cloud API OAuth consent screen. You don't need a redirect uri.

Create oauth credentials for desktop.

Save your client_id as `gmail_client_id.txt`, save your client_secret as `gmail_client_secret.txt`.

Host a local web server on port 8080. Run `mailer_manual_authorize` with those.

Get back your authorization code from the redirect url. This part basically can barely even be automated because you have to select your account and authorize access.

Open postman or something. Create a post request to `https://oauth2.googleapis.com/token`. With this body:

```
client_id={your_client_id}
client_secret={your_client_secret}
grant_type=authorization_code
code={your_authorization_token}
rediect_uri=http://127.0.0.1:8080
```

Save your refresh token to `gmail_refresh_token.txt`.

Call `mailer_authorize` with your client_id, client_secret, and refresh_token. You are now authenticated.

Expect everything to change for no reason at all and break in 2 years because it's google and they suck ass at everything they do.
