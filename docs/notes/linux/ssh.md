# SSH

## Tunneling

* Access remote server behind the firewall.

For example access app running on 8080 port for server x.y.z.a

`ssh -L 9000:localhost:8080 ec2-user@x.y.z.a`

Now just open the http://localhost:9000

* Expose the local port to remote server

`ssh -R 9000:localhost:3000 user@example.com`

Now the remote server could access you local app on remote address localhost:9000


# References:

- https://blog.trackets.com/2014/05/17/ssh-tunnel-local-and-remote-port-forwarding-explained-with-examples.html
