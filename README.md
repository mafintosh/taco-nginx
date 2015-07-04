# taco-nginx

Bash script that runs a service and forwards a subdomain to it using nginx when it listens to `$PORT`

```
npm install -g taco-nginx
```

We recommend using latest stable nginx (>1.8.0). If you are on Ubuntu LTS for example you may need to do this:

```
add-apt-repository ppa:nginx/stable
apt-get update
apt-get install nginx
```

## Usage

First write a service (in any language) similar to this

``` js
var http = require('http')
var server = http.createServer(function (req, res) {
  console.log('Got request!', req.url)
  res.end('hello world\n')
})

server.listen(process.env.PORT, function () {
  console.log('Server is listening...')
})
```

Assuming the above file is called `server.js` and you have `nginx` running you can now do

``` sh
taco-nginx --name my-service node server.js
```

taco-nginx will now spawn `node server.js`, wait for it to listen to the port specified in
`$PORT` and then have nginx route requests to `my-service.*` to it.

If you don't specify `--name` it will see if you have a `package.json` and use the name field

``` sh
taco-nginx node server.js # uses name from package.json
```

For a full list of options run

```
taco-nginx --help
```

## License

MIT
