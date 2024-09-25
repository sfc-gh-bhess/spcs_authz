# Use nginx to make the Authorization header available to SPCS endpoints
This project demonstrates how we can use nginx and [xhook]()
to get the `Authorization` header into containers in SPCS.
Today, SPCS explicitly strips the `Authorization` header on
all requests to public endpoints.

The xhook JavaScript library will allow you to modify HTTP
requests in the webapp prior to sending to the server (as 
well as being able to modify responses from the server).

The main idea is that we can take the `Authorization` header
and copy it to another header, `X-Spcs-Authorization`. This
will put the value in a header that SPCS will not strip. Then,
we can use rewrite rules in nginx to copy the value of the
`X-Spcs-Authorization` header back to the `Authorization`
header before sending to the container endpoint.

We use another nginx directive (`sub_filter`) to modify the 
HTML being served to put in a few `<script>` statements at the
end of the `<head> ... </head>` block. In this way, the source
does not need to change at all.

The router image in this project can be added to any existing
application being hosted in SPCS and nginx will take care of 
modifying the served HTML and modifying the incoming requests
so that by the time the request gets to the hosted container
the `Authorization` header will be available. All without needing
to change the existing application.

## Description
This project includes 2 Docker images:
* A backend service written in Flask that has 2 endpoints
  * the `/headers` endpoint which will return all of the
    headers that the endpoint received.
  * the `/test` endpoint serves a simple HTML page to test
    the `/headers` endoint. It allows you set the value for
    the `Authorization` header so you can see how it is plumbed
    through.
* A router service, which is a configured nginx container to
  proxy to the backend service.

### Details on nginx
There are 2 things that we are doing with the nginx config

#### Adding the scripts
First, we are injecting some `<script>` tags at the end of
the `<head>` block. The first loads the xhook library:
```html
<script src="//unpkg.com/xhook@latest/dist/xhook.min.js"></script>
```

The second uses the xhook library to intercept HTTP requests and copy
the `Authorization` header into the `X-SPCS-Authorization` header. This
will allow this header to not be stripped by SPCS:
```html
<script>
  xhook.before(function(request) { 
    if ("Authorization" in request.headers) {
      request.headers["X-SPCS-Authorization"]=request.headers["Authorization"] 
    }
  });
</script>
```

We do this by using the `sub_filter` directive to replace the `</head>`
tag with these 2 `<script>` tags (and the `</head>` tag).

#### Restoring the Authorization header
The second thing we are doing is to copy the `X-SPCS-Authorization` header
into the `Authorization` header. We can do this using the `map` and 
`proxy_set_header` directives. 

We use the `map` directive to set an internal variable to the value
of the `X-SPCS-Authorization` header if it is present, or to the empty string.
```
  map $http_x_spcs_authorization $authz {
    '~.' $http_x_spcs_authorization;
    default '';
  }
```

We then use this `$authz` variable to set the `Authorization` header to this
value, if it is not the empty string:
```
  proxy_set_header Authorization $authz;
```


## Configuration
Use the included configuration script to set up the necessary
resources with the proper value for the `IMAGE REPOSITORY`. To
get the URL of the `IMAGE REPOSITORY` run the following SQL:
```sql
SHOW IMAGE REPOSITORIES;
```

Once you have the URL, run:
```bash
bash ./configure.sh
```
and enter the URL for the `IMAGE REPOSITORY`.

This will generate a `Makefile`, `backend.yaml` and `router.yaml`

## Docker
We will build the images using Docker. First we need to log
into the Snowflake account to access the `IMAGE REPOSITORY`.
We will use SnowCLI for this:
```bash
snow spcs image-registry login
```
Make sure to use the connection for your Snowflake account.
If it is not your default SnowCLI connection, use
```bash
snow scs image-registry login -c <connection>
```

Next, we can build the images and push them to Snowflake using 
`make`:
```bash
make all
```

## SPCS
Once the images have been pushed to Snowflake, we are ready to create
our services.

We will need an `EXTERNAL ACCESS INTEGRATION` in order to access
the `xhook` package in our webpage. This is how we can modify the
Content Security Policy to allow loading from external sites.

```sql
CREATE OR REPLACE NETWORK RULE nr_unpkg
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('unpkg.com')
;
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION eai_unpkg
    ALLOWED_NETWORK_RULES = ( nr_unpkg )
    ENABLED = TRUE
;

```

You will need a `COMPUTE POOL`. Feel free to use an existing
`COMPUTE POOL`, but if you need one, run
```sql
   CREATE COMPUTE POOL authz_compute_pool
      MIN_NODES = 1
      MAX_NODES = 1
      INSTANCE_FAMILY = CPU_X64_XS;
```

We are now ready to create our services. We will first create
the backend service and wait for it to start before creating 
the router service.
```sql
CREATE SERVICE authz_backend
  IN COMPUTE POOL POOL1
  FROM SPECIFICATION $$
spec:
  containers:
    - name: backend
      image: REPOSITORY_URL/spcs_authz
  endpoints:
    - name: backend
      port: 8001
serviceRoles:
- name: backend
  endpoints:
  - backend
  $$
;
```

Use the following to see if the service has started and is up and running:
```sql
SELECT SYSTEM$GET_SERVICE_STATUS('authz_backend');
SELECT SYSTEM$GET_SERVICE_LOGS('authz_backend', 0, 'backend', 100);
```

Once the backend service is up and running, it's time to start
the router service:
```sql
CREATE SERVICE authz_router
  IN COMPUTE POOL POOL1
  FROM SPECIFICATION $$
spec:
  containers:
    - name: router
      image: REPOSITORY_URL/spcs_authz_router
      args:
        - /=http://authz-backend:8001/
  endpoints:
    - name: router
      port: 80
      public: true
serviceRoles:
- name: app
  endpoints:
  - router
  $$
  EXTERNAL_ACCESS_INTEGRATIONS = ( EAI_UNPKG )
;
```

We can see when this service has started by running:
```sql
SELECT SYSTEM$GET_SERVICE_STATUS('authz_router');
SELECT SYSTEM$GET_SERVICE_LOGS('authz_router', 0, 'router', 100);
```

Once that service has started, we will want to grant usage of the
endpoint to users. For example, if there is a role `SANDBOX` that we
would like to allow access to the endpoint in the `AUTHZ_ROUTER` service,
we can run the following:
```sql
GRANT SERVICE ROLE authz_router!app TO ROLE sandbox;
```

We will now need to use the `AUTHZ_ROUTER`'s endpoint to access the
test page, so we need the URL. To get that, run:
```sql
SHOW ENDPOINTS IN SERVICE authz_router;
```

### Test
Navigate to the service URL and log in using a user that either has the
role that created the service or has been granted the `authz_router!app` 
service role.  Once you log in, add the suffix `/test` to the URL to get
access to the test page.

Click the "Get Headers" button and see the header we sent (the 
`Authorization` header and its value), and the headers that the
backend received. Notice that the `Authorization` header was received
by the backend. You can also see the `X-Spcs-Authorization` header we
used to tunnel the `Authorization` header through.

Feel free to clear the results by clicking the "Clear Headers" button. 
Also, feel free to enter a different value for the `Authorization` header
and click "Get Headers" to see that it has been plubmed through to the
backend.
