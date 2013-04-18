# tentd-admin

tentd-admin implements a very basic administration interface for
[tentd](https://github.com/tent/tentd). It also mounts tentd as a Rack app, so
it's the easiest way to get started with a [Tent Protocol](http://tent.io)
implementation.

## Quick Start with Heroku

### Heroku

```shell
git clone git://github.com/tent/tentd-admin.git
cd tentd-admin
heroku create --addons heroku-postgresql:dev
heroku pg:promote $(heroku pg | head -1 | cut -f2 -d" ")
heroku config:add ADMIN_USERNAME=admin ADMIN_PASSWORD=password ADMIN_ASSET_MANIFEST=./public/assets/manifest.json COOKIE_SECRET=$(openssl rand -hex 32)
git push heroku master
heroku run rake db:migrate
heroku open
```

The last command will open your Tent server in a web browser. Your Tent **entity** is in the address bar (example: `https://quiet-tent-123.herokuapp.com`).

Add `/admin` to the end of the web address to continue setup (example: `https://quiet-tent-123.herokuapp.com/admin`)

Your username will be `admin`, and password `password` (unless you chose something different in the setup commands above). 

You can edit your profile and manage apps in **TentAdmin**.

You'll need another Tent app to get started. Check out [TentStatus](https://github.com/tent/tent-status) or some of the [other apps](https://github.com/tent/tent.io/wiki/Related-projects) that are already available.

## Standard Installation

### Ruby

tentd-admin requires Ruby 1.9. If you don't have Ruby 1.9 you can use your
operating system's package manager to install it.

#### OS X

The easiest way to get Ruby 1.9 on OS X is to use [Homebrew](http://mxcl.github.com/homebrew/).

```shell
brew install ruby
```

If you need to switch between ruby versions, use
[rbenv](https://github.com/sstephenson/rbenv) and
[ruby-build](https://github.com/sstephenson/ruby-build).


#### Ubuntu

```shell
sudo apt-get install build-essential ruby1.9.1-full libxml2 libxml2-dev libxslt1-dev
sudo update-alternatives --config ruby # make sure 1.9 is the default
```


### PostgreSQL

tentd-admin requires a PostgreSQL database.

#### OS X

Use [Homebrew](http://mxcl.github.com/homebrew/) or [Postgres.app](http://postgresapp.com/).

```shell
brew install postgresql
createdb tent_server
```


### Bundler

Bundler is a project dependency manager for Ruby.

```
gem install bundler
```


### Starting tentd-admin

Clone this repository, and `cd` into the directory. This should start the app:

```shell
bundle install
DATABASE_URL=postgres://localhost/tent_server bundle exec rake db:migrate
DATABASE_URL=postgres://localhost/tent_server ADMIN_USERNAME=admin ADMIN_PASSWORD=admin bundle exec puma -p 3000
```

If all goes well, you'll have a Tent server available at
[http://localhost:3000/](http://localhost:3000/) and you can log into the admin
interface at [http://localhost:3000/admin](http://localhost:3000/admin) with the
username and password `admin`. After setting up the base profile in the admin,
this should show the profile JSON:

```shell
curl http://localhost:3000/profile
```

### Environment Variables

Some environment variables should be set to configure tentd and tentd-admin.

| Name | Required | Description |
| ---- | -------- | ----------- |
| DATABASE_URL | Required | The connection details for the PostgreSQL database (ex: `postgres://user:password@host/dbname`) |
| ADMIN_USERNAME | Required | The username used to access tentd-admin. |
| ADMIN_PASSWORD | Required | The password used to access tentd-admin. |
| COOKIE_SECRET | Optional | The session secret. Set if you don't want a new session every time you reboot the app. |
| RACK_ENV | Optional | Defaults to `development`. Set to `production` for production deployments. |
| SERVE_ASSETS | Optional | Should be set if `RACK_ENV` is set to `production` and assets aren't on a CDN. |
| ADMIN_ASSET_MANIFEST | Optional | Should be set if `RACK_ENV` is set to `production` and `SERVE_ASSETS` is not set. |
| TENT_ENTITY | Optional | Set to the exact Tent Entity URL if tentd is not responding to requests at the URL. |
| TENT_SUBDIR | Optional | Treat all URLs as being under a subdirectory, e.g. "/tent". |

### HTTP Headers

If you are running a reverse-proxy in front of tentd, the `X-Forwarded-Port` and `Host` request headers need to be set.

#### nginx

```
location / {
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-Proto https;
  proxy_set_header X-Forwarded-Port 443;
  proxy_pass http://tentd;
}
```

#### apache

```
<VirtualHost tentd.example.com>
ProxyRequests Off
ProxyPreserveHost On
ProxyPass / http://localhost:3000/
ProxyPassReverse / http://localhost:3000

RequestHeader set Host tentd.example.com
RequestHeader set X-Forwarded-Proto https
RequestHeader set X-Forwarded-Port 443

</VirtualHost>
```

## Updating to 0.2

You'll need to create a table `schema_info` and set `schema_info.version = 1`, then run `rake db:migrate`:

```sql
CREATE TABLE schema_info (version integer);
INSERT INTO schema_info (version) VALUES (1);
```

### Heroku

```
heroku run rake db:migrate
```

### Ruby

```
DATABASE_URL=postgres://localhost/tent_server bundle exec rake db:migrate
```

## Contributing

Currently tentd-admin only implements app authentication and following creation.
These are some things that could be done to improve the app:

- Add support for managing (CRUD) all of the data in Tent: profiles, followers,
  followings, apps, and posts.
- Add a log in the UI of API calls to tentd for easy debugging.
- Write tests and refactor the code.
- Make a pretty UI.
- Allow creation of the database and setting username/password from the UI.
- Show better app details in OAuth flow (icon, post/profile type details)
- Replace tentd database hooks with API calls
- Create an omnibus-style package that installs and configures everything needed
  to get started with tentd-admin.
