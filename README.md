# tentd-admin

tentd-admin implements a very basic administration interface for
[tentd](https://github.com/tent/tentd). It also mounts tentd as a Rack app, so
it's the easiest way to get started with a [Tent Protocol](http://tent.io)
implementation.

## Getting Started

In order to get tentd-admin running, you need Ruby 1.9, Bundler, and PostgreSQL.

```shell
createdb tent_server
bundle install
DATABASE_URL=postgres://localhost/tent_server ADMIN_USER=admin ADMIN_PASSWORD=admin bundle exec puma start -p 3000
open http://localhost:3000
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
