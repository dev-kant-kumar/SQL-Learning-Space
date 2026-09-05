Absolutely. Let's do this properly. We'll build a **PostgreSQL Connection Pooling** reference from fundamentals to production, one section at a time.

Since you're putting this into `README.md`, I'll keep each section **clean, technical, and reusable as study notes**—not conversational fluff.

# PostgreSQL Connection Pooling — Complete Notes

## 1. What Is a PostgreSQL Connection?

A PostgreSQL connection is a communication channel established between an application and a PostgreSQL database server.

When a backend application needs to execute a SQL query, it needs a connection through which it can communicate with PostgreSQL.

A simplified flow looks like this:

```text
Node.js Application
        │
        │  Connection
        ▼
PostgreSQL Server
        │
        ▼
   Execute SQL
        │
        ▼
     Result
```

For example, suppose our Node.js application wants to execute:

```sql
SELECT * FROM users;
```

The application needs an established database connection to send this SQL statement to PostgreSQL and receive the result.

### What happens when a connection is established?

At a high level:

```text
Application
    │
    │  TCP connection
    ▼
PostgreSQL Server
    │
    │  Authentication
    ▼
PostgreSQL Session
    │
    ▼
Ready to execute queries
```

A connection involves more than simply "opening a socket."

The client and server establish communication, authenticate the client, negotiate/use the PostgreSQL protocol, and create a database session in which SQL commands can be executed.

### Connection vs Query

These are two different things:

**Connection:**

> The communication channel/session between your application and PostgreSQL.

**Query:**

> A SQL operation executed through that connection.

For example:

```text
Connection
    │
    ├── SELECT ...
    ├── INSERT ...
    ├── UPDATE ...
    └── DELETE ...
```

A single connection can execute many queries over its lifetime.

This distinction is fundamental to understanding connection pooling.

---

## Why does the application need connections?

Your Node.js application and PostgreSQL are separate processes, potentially even running on separate machines.

For example:

```text
┌──────────────────────┐
│      Node.js         │
│     Application      │
└──────────┬───────────┘
           │
           │ Network
           │
┌──────────▼───────────┐
│     PostgreSQL       │
│       Server         │
└──────────────────────┘
```

The connection provides the communication path between them.

Without a connection, your application cannot simply send SQL directly to PostgreSQL.

---

## A Connection Is a Resource

Database connections aren't free.

A PostgreSQL connection consumes resources on both sides:

```text
Node.js
   │
   └── Client-side resources

PostgreSQL
   │
   └── Server-side resources
```

PostgreSQL traditionally uses a server process/backend for each client connection, so having a large number of concurrent connections can consume significant server resources.

Therefore, applications need to manage database connections carefully.

This is one of the fundamental reasons connection pooling exists.

---

## Connection Lifetime

A connection can remain open and be reused for multiple database operations:

```text
Open Connection
      │
      ├── Query 1
      ├── Query 2
      ├── Query 3
      ├── Query 4
      │
      ▼
Close Connection
```

Compare that with repeatedly creating connections:

```text
Open → Query → Close
Open → Query → Close
Open → Query → Close
Open → Query → Close
```

The second approach creates unnecessary connection-establishment overhead.

A pool allows us to keep connections available for reuse.

---

## Key Takeaways

Remember these points:

* A PostgreSQL connection is a communication channel/session between an application and PostgreSQL.
* Queries are executed **through connections**.
* A connection can execute multiple queries during its lifetime.
* Establishing a connection has overhead.
* Connections consume resources.
* PostgreSQL connections should therefore be managed carefully.
* **Connection pooling exists largely to reuse database connections instead of repeatedly creating and destroying them.**

### Mental Model

```text
Connection ≠ Query

Connection
    │
    ├── Query
    ├── Query
    ├── Query
    └── Query
```

**Core idea:**

> A database connection is a reusable communication session through which an application sends SQL operations to PostgreSQL.

---

# 2. What Actually Happens When Node.js Connects to PostgreSQL?

Before understanding pooling, you should understand what happens during a **single PostgreSQL connection**.

Suppose you have a Node.js backend using the `pg` package:

```js
import pg from "pg";

const { Client } = pg;

const client = new Client({
  host: "localhost",
  port: 5432,
  user: "postgres",
  password: "password",
  database: "myapp",
});

await client.connect();
```

When `client.connect()` executes, several things happen.

---

## 2.1 The Application Needs PostgreSQL's Address

Your Node.js application needs to know where PostgreSQL is running.

Typically:

```text
Host:     localhost
Port:     5432
Database: myapp
User:     postgres
Password: ********
```

For example:

```text
Node.js
   │
   │ host = localhost
   │ port = 5432
   ▼
PostgreSQL
```

The default PostgreSQL port is:

```text
5432
```

The host could be:

```text
localhost
127.0.0.1
database.example.com
10.0.0.5
```

depending on where your database is running.

---

# 2.2 TCP Connection Is Established

PostgreSQL communicates over the network.

So the client first establishes a network connection to the PostgreSQL server.

Simplified:

```text
Node.js Application
        │
        │ TCP
        ▼
PostgreSQL Server
```

If PostgreSQL is running locally:

```text
Node.js
   │
   │ TCP → localhost:5432
   ▼
PostgreSQL
```

If PostgreSQL is running on another machine:

```text
Node.js Server
      │
      │ Network
      ▼
Database Server
```

This network connection provides the underlying communication channel.

---

# 2.3 PostgreSQL Authentication

After communication is established, PostgreSQL needs to determine whether the client is allowed to connect.

The client provides credentials such as:

```text
Username
Password
Database
```

PostgreSQL verifies the authentication according to its configured authentication rules.

For example:

```text
Node.js
   │
   │ "I want to connect as postgres"
   ▼
PostgreSQL
   │
   │ Authentication
   ▼
Access granted
```

If authentication fails:

```text
Node.js
   │
   ▼
PostgreSQL
   │
   ✕ Authentication failed
```

The connection isn't established successfully.

---

# 2.4 PostgreSQL Creates a Session

Once authentication succeeds, PostgreSQL establishes a database session for that client connection.

Think of it as:

```text
TCP connection
      ↓
PostgreSQL connection
      ↓
Database session
      ↓
Ready for SQL
```

The session maintains state associated with that connection.

For example, certain settings, temporary objects, prepared statements, and transaction state can be associated with the session.

This becomes **very important when we later discuss transactions and connection pooling**.

---

# 2.5 PostgreSQL Has Server-Side Resources for the Connection

A PostgreSQL connection isn't just a lightweight number stored somewhere.

PostgreSQL allocates server-side resources to handle the connection.

Conceptually:

```text
Node.js
   │
   │ Connection
   ▼
PostgreSQL
   │
   └── Resources associated with client
```

PostgreSQL's architecture traditionally uses a server-side process for each client connection.

Therefore, having hundreds or thousands of connections isn't free.

For example:

```text
100 connections
      ↓
100 PostgreSQL client connections
      ↓
Significant server-side resource usage
```

This is one of the reasons connection count needs to be controlled.

---

# 2.6 The PostgreSQL Protocol

Node.js doesn't send raw JavaScript objects to PostgreSQL.

The PostgreSQL client library communicates with PostgreSQL using the **PostgreSQL wire protocol**.

Your application does:

```js
await client.query("SELECT * FROM users");
```

But underneath:

```text
JavaScript
    ↓
pg client library
    ↓
PostgreSQL wire protocol
    ↓
Network
    ↓
PostgreSQL
```

The `pg` library handles the protocol details for you.

You therefore don't need to manually implement the PostgreSQL protocol.

---

# 2.7 The Connection Is Now Ready

After the connection process succeeds:

```text
Node.js
   │
   │
   ▼
┌─────────────────────┐
│ PostgreSQL Session   │
│                     │
│ Ready for queries    │
└─────────────────────┘
```

Now the application can execute:

```sql
SELECT * FROM users;
```

or:

```sql
INSERT INTO users (...) VALUES (...);
```

or:

```sql
UPDATE users SET ...;
```

etc.

---

# 2.8 One Connection Can Execute Multiple Queries

This is an extremely important concept.

You don't need to establish a completely new connection for every SQL query.

For example:

```text
Connection
    │
    ├── SELECT
    │
    ├── INSERT
    │
    ├── UPDATE
    │
    └── DELETE
```

The connection can remain open.

That's what makes reuse possible.

And **connection pooling takes advantage of exactly this property**.

---

# 2.9 What Happens When the Connection Closes?

Eventually the application can close the connection:

```js
await client.end();
```

Conceptually:

```text
Node.js
   │
   │ Close
   ▼
PostgreSQL
   │
   ▼
Session ends
   │
   ▼
Connection resources released
```

So the simplified lifecycle is:

```text
┌───────────────┐
│ Create Client │
└───────┬───────┘
        ↓
   TCP Connection
        ↓
   Authentication
        ↓
   PostgreSQL Session
        ↓
   Execute Queries
        ↓
   Connection Remains Open
        ↓
   client.end()
        ↓
   Session Ends
```

---

# 2.10 Why This Matters for Connection Pooling

Now we can see the problem.

Imagine your backend receives 1,000 HTTP requests.

A naive architecture might do:

```text
Request 1
   ↓
Create PostgreSQL connection
   ↓
Query
   ↓
Close

Request 2
   ↓
Create PostgreSQL connection
   ↓
Query
   ↓
Close

Request 3
   ↓
Create PostgreSQL connection
   ↓
Query
   ↓
Close

...
```

That's wasteful because establishing and tearing down connections repeatedly has overhead.

Instead, we can establish a limited number of connections and reuse them:

```text
                 PostgreSQL
                      ▲
                      │
             ┌────────┴────────┐
             │ Connection Pool  │
             ├─────────────────┤
             │ Connection 1    │
             │ Connection 2    │
             │ Connection 3    │
             │ Connection 4    │
             │ Connection 5    │
             └────────┬────────┘
                      ▲
                      │
                 Node.js
                      ▲
                      │
              HTTP Requests
```

And **that is the problem connection pooling solves**.

---

# Key Takeaways

You should be able to explain this sequence:

```text
Node.js
   ↓
Find PostgreSQL host + port
   ↓
Establish TCP connection
   ↓
Authenticate
   ↓
PostgreSQL establishes a session
   ↓
Connection is ready
   ↓
Execute SQL queries
   ↓
Connection remains available
   ↓
Eventually close connection
```

### Most important concepts

* PostgreSQL communicates over a network connection.
* `5432` is the conventional default PostgreSQL port.
* Authentication happens when establishing a connection.
* A successful connection corresponds to a PostgreSQL session.
* The session can execute multiple queries.
* Connections consume server-side resources.
* Creating and destroying connections repeatedly has overhead.
* A long-lived connection can be reused.
* **Connection pooling builds on this by maintaining multiple reusable connections.**

### Mental Model

> **A PostgreSQL connection is a long-lived communication/session channel between your application and PostgreSQL. Establishing that channel costs resources, so backend applications generally reuse connections instead of creating one for every query or HTTP request.**

---

# 3. Why Opening a New PostgreSQL Connection Per Request Is a Bad Idea

Now that we understand what a PostgreSQL connection is and what happens when one is established, we can understand **why backend applications don't normally create a new database connection for every HTTP request**.

This is the problem that connection pooling is designed to solve.

---

## 3.1 The Naive Approach

Imagine an API:

```text
GET /users
```

A naive implementation might do this:

```text
HTTP Request
     ↓
Create PostgreSQL connection
     ↓
Authenticate / establish session
     ↓
Execute query
     ↓
Close connection
     ↓
Send HTTP response
```

For one request, this might appear perfectly reasonable.

The problem becomes obvious when there are many requests.

```text
Request 1 → Open → Query → Close
Request 2 → Open → Query → Close
Request 3 → Open → Query → Close
Request 4 → Open → Query → Close
Request 5 → Open → Query → Close
...
```

You're repeatedly paying the cost of establishing and destroying connections.

---

# 3.2 Connection Establishment Has Overhead

Creating a database connection isn't instantaneous.

At a simplified level:

```text
Application
    ↓
Network connection
    ↓
PostgreSQL accepts connection
    ↓
Authentication
    ↓
Session established
    ↓
Ready for query
```

Every time you create a new connection, some of this work has to happen again.

Therefore:

```text
New Connection
      ↓
Connection overhead
      ↓
Query
```

is generally less efficient than:

```text
Existing Connection
      ↓
Query
```

when a reusable connection is already available.

---

# 3.3 It Adds Latency

Suppose your actual SQL query is very fast:

```sql
SELECT * FROM users WHERE id = 1;
```

If the query itself takes only a few milliseconds, repeatedly establishing connections can become a significant portion of the request's total database-related latency.

Conceptually:

```text
Without reuse:

Connection setup     ███████
Query                 ██
Connection teardown   ███
```

versus:

```text
With reuse:

Acquire connection   █
Query                 ██
Release connection   █
```

The exact timings depend on the environment, but the principle is important:

> **Don't repeatedly pay an expensive setup cost when the resource can be safely reused.**

---

# 3.4 High Traffic Makes the Problem Worse

Consider:

```text
10 requests/second
```

A poorly designed application might repeatedly create and close connections.

Now imagine:

```text
1,000 requests/second
```

The application could potentially generate a huge amount of connection churn.

```text
Request
   ↓
New connection
   ↓
Query
   ↓
Close
```

repeated thousands of times.

That's unnecessary work.

With pooling:

```text
             ┌── Connection 1
             ├── Connection 2
Requests ────┼── Connection 3
             ├── Connection 4
             └── Connection 5
```

the same connections can serve many requests over time.

---

# 3.5 PostgreSQL Connections Consume Resources

This is one of the most important reasons.

Each PostgreSQL connection consumes resources on the PostgreSQL server.

PostgreSQL traditionally uses a server-side process for each client connection.

So:

```text
1 application connection
        ↓
PostgreSQL handles 1 client connection
```

and:

```text
100 application connections
        ↓
PostgreSQL handles 100 client connections
```

Those connections consume memory and other server resources.

Therefore, creating connections indiscriminately can put unnecessary pressure on PostgreSQL.

---

# 3.6 PostgreSQL Has a Connection Limit

PostgreSQL has a configuration setting called:

```text
max_connections
```

which limits the number of concurrent client connections PostgreSQL will accept, subject to PostgreSQL's configuration and reserved connection capacity.

For example, conceptually:

```text
max_connections = 100
```

does **not** mean your application should blindly create 100 connections.

It means PostgreSQL has a finite connection capacity.

There may also be other applications connecting to the same database:

```text
                    PostgreSQL
                        │
          ┌─────────────┼─────────────┐
          ↓             ↓             ↓
       Backend       Admin tool     Worker
       20 conn        2 conn        10 conn
```

All of them consume connection capacity.

This becomes especially important in production.

---

# 3.7 Connection Storms

Here's a nasty scenario.

Imagine your server starts receiving many requests simultaneously:

```text
100 requests
     ↓
100 attempts to create DB connections
     ↓
PostgreSQL receives connection attempts
     ↓
Resource pressure
```

A burst like this can cause unnecessary connection churn and potentially overwhelm the database.

A connection pool provides a controlled number of database connections:

```text
100 requests
     ↓
     Pool
     ↓
 ┌───┼───┬───┬───┐
 C1  C2  C3  C4  C5
```

Only a bounded number of operations can actively use pool connections at once; other database operations can wait for a connection to become available.

---

# 3.8 Connection Creation Is Different From Query Execution

This distinction is worth remembering:

```text
Connection establishment
```

and:

```text
SQL execution
```

are separate activities.

For example:

```text
Create connection
       ↓
     Query
       ↓
     Query
       ↓
     Query
       ↓
Close connection
```

If you create a connection for every query:

```text
Create → Query → Close
Create → Query → Close
Create → Query → Close
```

you're repeatedly paying the connection-establishment cost.

A reusable connection allows:

```text
Create
  ↓
Query
  ↓
Query
  ↓
Query
  ↓
Reuse
```

---

# 3.9 What About One Single Connection?

You might now think:

> "Okay, then I'll just create one PostgreSQL connection and use it for everything."

That solves one problem, but introduces another.

Suppose:

```text
1 PostgreSQL connection
```

and multiple requests need the database:

```text
Request A ─┐
Request B ─┤
Request C ─┼──→ ONE connection
Request D ─┤
Request E ─┘
```

Now database work can become constrained by that single connection.

You don't want to create **too many** connections, but you also don't necessarily want **only one**.

This is where the idea of a **pool of connections** comes in.

---

# 3.10 The Solution: Connection Pooling

Instead of:

```text
Every request
      ↓
New connection
      ↓
Query
      ↓
Close
```

or:

```text
Entire application
      ↓
ONE connection
```

we use:

```text
                Connection Pool
              ┌────┬────┬────┬────┐
              │ C1 │ C2 │ C3 │ C4 │
              └────┴────┴────┴────┘
                 ▲    ▲    ▲
                 │    │    │
              Requests
```

Connections are created and maintained by the pool.

A request obtains an available connection, performs its database work, and then returns the connection to the pool.

```text
Request
   ↓
Acquire
   ↓
Connection
   ↓
Execute query
   ↓
Release
   ↓
Pool
```

The connection remains available for another request.

---

# 3.11 Connection Reuse

Suppose the pool contains:

```text
C1
C2
C3
C4
C5
```

Request A gets C1:

```text
Request A → C1
```

After the query:

```text
Request A
    ↓
C1
    ↓
Pool
```

Then Request B can reuse it:

```text
Request B → C1
```

The same physical database connection can therefore serve many requests throughout the application's lifetime.

```text
C1
 │
 ├── Request A
 ├── Request B
 ├── Request F
 ├── Request K
 └── Request Z
```

That's the fundamental efficiency benefit.

---

# 3.12 Pooling Controls Concurrency

Pooling isn't just about reuse.

It also gives your application a mechanism for controlling how many database connections it maintains.

For example:

```text
max pool size = 10
```

Conceptually:

```text
          100 HTTP requests
                  ↓
             ┌─────────┐
             │  Pool   │
             │ max =10 │
             └────┬────┘
                  ↓
          ┌───────┼───────┐
          ↓       ↓       ↓
         C1      C2      ... C10
```

If all connections are busy, additional database operations can wait rather than causing the application to create unlimited new connections.

This provides **backpressure** at the database-access layer.

---

# 3.13 Why Pooling Is Better

Let's compare the approaches.

### Without pooling

```text
Request
   ↓
Create connection
   ↓
Query
   ↓
Destroy connection
```

Repeated continuously.

Problems:

* Connection establishment overhead
* Connection teardown overhead
* More latency
* Connection churn
* Increased database resource usage
* Difficult to control connection count
* Poor behaviour under high concurrency

### With pooling

```text
             Pool
        ┌────┬────┬────┐
        │ C1 │ C2 │ C3 │
        └────┴────┴────┘
          ↑    ↑    ↑
        Requests
```

Benefits:

* Connections are reused
* Less connection-establishment overhead
* Lower connection churn
* Bounded database connections
* Better handling of concurrent requests
* Better resource utilisation

---

# 3.14 Important: Pooling Doesn't Make Queries Faster

This is a subtle but important point.

Connection pooling does **not** magically make:

```sql
SELECT * FROM huge_table;
```

execute faster.

It primarily avoids repeatedly establishing connections and manages connection concurrency.

So:

```text
Connection pooling
       ≠
Query optimisation
```

Query performance still depends on things such as:

* indexes
* query structure
* execution plans
* table size
* database resources
* locking
* network latency

Pooling solves a **connection-management problem**, not every database-performance problem.

---

# 3.15 The Backend Mental Model

At this point, your architecture should look like:

```text
                         PostgreSQL
                             ▲
                             │
                    Database Connections
                             │
                    ┌────────┴────────┐
                    │ Connection Pool │
                    └────────┬────────┘
                             ▲
                             │
                       Node.js App
                             ▲
                             │
                       HTTP Requests
```

And each request follows roughly:

```text
HTTP Request
     ↓
Route Handler
     ↓
Service / Repository
     ↓
Pool
     ↓
Acquire connection
     ↓
Execute SQL
     ↓
Release connection
     ↓
HTTP Response
```

---

# Key Takeaways

Remember these:

1. **Creating a PostgreSQL connection has overhead.**
2. Creating a new connection for every HTTP request creates unnecessary connection churn.
3. PostgreSQL connections consume server resources.
4. PostgreSQL has a finite connection capacity.
5. A single connection can be reused for multiple queries.
6. One connection for the entire application can become a concurrency bottleneck.
7. A connection pool provides a middle ground:

   * multiple reusable connections
   * controlled connection count
   * connection reuse
   * better concurrency management
8. When all pool connections are busy, additional operations can wait for an available connection.
9. Connection pooling improves connection management; it does **not** replace query optimisation.

### The core problem

```text
❌ Every request:

Request
   ↓
Create connection
   ↓
Query
   ↓
Close connection
```

### The solution

```text
✅ Pool:

             ┌── Connection 1
             ├── Connection 2
Requests ────┼── Connection 3
             ├── Connection 4
             └── Connection 5

Request
   ↓
Acquire
   ↓
Query
   ↓
Release
   ↓
Reuse
```

> **Connection pooling exists because database connections are relatively expensive resources. Instead of repeatedly creating and destroying connections, an application maintains a controlled set of reusable connections and shares them across database operations.**

---

# 4. What Is Connection Pooling?

Now we can define connection pooling properly.

You've already seen **why** we need it. This section focuses on **what a pool actually is and how it manages connections**.

---

## 4.1 Definition

**Connection pooling** is a technique where an application maintains a collection of reusable database connections and shares those connections among multiple database operations.

Instead of creating a new PostgreSQL connection every time the application needs the database, the application creates a **pool of connections** and reuses them.

```text
                    Node.js Application
                           │
                           ▼
                  ┌─────────────────┐
                  │ Connection Pool │
                  ├─────────────────┤
                  │ Connection 1    │
                  │ Connection 2    │
                  │ Connection 3    │
                  │ Connection 4    │
                  │ Connection 5    │
                  └────────┬────────┘
                           │
                           ▼
                      PostgreSQL
```

The pool acts as a **manager of database connections**.

---

# 4.2 The Basic Idea

Think of connections as reusable resources.

Suppose your pool has five connections:

```text
C1
C2
C3
C4
C5
```

A request needs to execute a query.

The pool gives it an available connection:

```text
Request A
    ↓
  Pool
    ↓
   C1
```

The query runs:

```text
Request A
    ↓
   C1
    ↓
PostgreSQL
```

When the database operation finishes, the connection is returned to the pool:

```text
Request A
    ↓
   C1
    ↓
  Pool
```

C1 isn't destroyed.

It's now available for another operation.

```text
Request B
    ↓
  Pool
    ↓
   C1
```

This is **connection reuse**.

---

# 4.3 A Pool Contains Connections

A connection pool isn't itself a PostgreSQL connection.

It is a **manager/container for multiple connections**.

```text
Pool
 │
 ├── Connection 1
 ├── Connection 2
 ├── Connection 3
 ├── Connection 4
 └── Connection 5
```

The pool is responsible for things such as:

* creating connections
* tracking connections
* handing connections out
* receiving released connections
* creating new connections when appropriate
* limiting the number of connections
* handling waiting operations
* removing unusable connections

The exact behaviour depends on the pooling library.

---

# 4.4 Three Important States

For learning connection pooling, understand these three concepts:

```text
1. Idle
2. Busy
3. Waiting
```

### Idle connection

A connection currently isn't being used by an operation.

```text
Pool
 ├── C1 → Idle
 ├── C2 → Idle
 └── C3 → Idle
```

It's available for another database operation.

---

### Busy connection

A connection is currently checked out and being used.

```text
Pool
 ├── C1 → Busy
 ├── C2 → Idle
 └── C3 → Idle
```

For example:

```text
Request A
    ↓
    C1
    ↓
Running SQL
```

---

### Waiting operation

Suppose all available connections are busy.

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

Then another request needs a connection:

```text
Request D
     ↓
    Pool
     ↓
No available connection
     ↓
   Wait
```

The request can wait for a connection to become available, subject to the pool/client timeout behaviour.

When C1 finishes:

```text
C1 → Available
```

the waiting operation can obtain it.

---

# 4.5 The Acquire → Use → Release Cycle

This is probably the **most important diagram in this entire topic**.

```text
              ┌─────────────┐
              │ Connection  │
              │     Pool    │
              └──────┬──────┘
                     │
                     │ Acquire
                     ▼
              ┌─────────────┐
              │ Connection  │
              │     C1      │
              └──────┬──────┘
                     │
                     │ Use
                     ▼
              ┌─────────────┐
              │ Execute SQL │
              └──────┬──────┘
                     │
                     │ Release
                     ▼
              ┌─────────────┐
              │ Connection  │
              │  back in    │
              │    Pool     │
              └─────────────┘
```

In simple terms:

```text
Acquire
   ↓
Use
   ↓
Release
   ↓
Reuse
```

That cycle is the heart of connection pooling.

---

# 4.6 Pooling Does Not Mean Sharing One Connection Simultaneously

This is a very important distinction.

Suppose:

```text
Pool
 ├── C1
 ├── C2
 └── C3
```

If Request A checks out C1:

```text
Request A → C1
```

another operation shouldn't simultaneously treat that same connection as independently available:

```text
Request A → C1
Request B → C1   ❌
```

Instead, Request B can get another available connection:

```text
Request A → C1
Request B → C2
Request C → C3
```

If no connection is available, Request D waits.

```text
Request D
    ↓
 Pool
    ↓
 Wait
```

So the pool manages **exclusive checkout of connections for operations that need them**.

---

# 4.7 Pool Size

A pool normally has a limit on how many connections it can maintain.

For example:

```text
max pool size = 5
```

Conceptually:

```text
Pool
 ├── C1
 ├── C2
 ├── C3
 ├── C4
 └── C5
```

At most five connections can be active in the pool according to that configured maximum, subject to the driver's exact behaviour and database topology.

If five are already in use:

```text
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

and another operation requests a connection:

```text
Request F
    ↓
  Pool
    ↓
No available connection
    ↓
Waiting
```

This is how a pool places a boundary around database connection usage.

---

# 4.8 Pooling Doesn't Mean All Connections Are Created Immediately

A common misconception is:

> "If I configure a pool with a maximum of 20, the application immediately creates 20 connections."

Not necessarily.

A pool can create connections as needed, depending on the pooling library and configuration.

For example, conceptually:

```text
Application starts
       ↓
Pool exists
       ↓
No/limited connections initially
       ↓
Requests need DB
       ↓
Pool creates connections
       ↓
Connections become reusable
```

This is why you need to distinguish between:

```text
Maximum pool size
```

and:

```text
Current number of connections
```

They are not necessarily the same.

---

# 4.9 Pooling Across Time

Imagine your application receives requests over time.

At 10:00:

```text
Request A → C1
Request B → C2
```

At 10:01:

```text
Request A finishes
Request B finishes
```

Now:

```text
C1 → Idle
C2 → Idle
```

At 10:02:

```text
Request C → C1
Request D → C2
```

The connections were reused.

You didn't need:

```text
Create C3
Create C4
```

just because new HTTP requests arrived.

---

# 4.10 Connection Pool vs Connection

Make sure this distinction is crystal clear:

| Connection                   | Connection Pool                    |
| ---------------------------- | ---------------------------------- |
| One database connection      | Manager of multiple connections    |
| Communicates with PostgreSQL | Manages connections                |
| Can execute queries          | Gives connections to operations    |
| Has session state            | Tracks connection availability     |
| Is a resource                | Controls a collection of resources |

Think:

```text
Connection = one car
Pool = parking/vehicle management system
```

The analogy isn't perfect, but it gives you the right intuition.

---

# 4.11 Pool vs Database

Another important distinction:

```text
Node.js
   ↓
Connection Pool
   ↓
Connections
   ↓
PostgreSQL Server
   ↓
Database
```

These aren't interchangeable terms.

### PostgreSQL Server

The PostgreSQL server process/service accepts client connections and executes database operations.

### Database

A PostgreSQL server can contain multiple databases.

### Connection

A client communication/session channel to PostgreSQL.

### Pool

A client-side mechanism for managing reusable connections.

So:

```text
Pool ≠ Database
Pool ≠ PostgreSQL Server
Pool ≠ Connection
```

---

# 4.12 What Does a Request Actually Get?

This is subtle.

When your application says:

```js
await pool.query("SELECT * FROM users");
```

the application doesn't necessarily manually choose:

```text
"Give me Connection 3."
```

The pool handles connection selection.

Conceptually:

```text
pool.query()
     ↓
Pool checks connections
     ↓
Find available connection
     ↓
Use connection
     ↓
Execute query
     ↓
Return connection
     ↓
Return result
```

The library abstracts away much of this management.

---

# 4.13 `pg.Pool` in Node.js

With PostgreSQL and Node.js, a common library is `pg`.

You can create a pool like this:

```js
import pg from "pg";

const { Pool } = pg;

const pool = new Pool({
  host: "localhost",
  port: 5432,
  user: "postgres",
  password: "password",
  database: "myapp",
  max: 10,
});
```

Here:

```js
max: 10
```

configures the maximum pool size for that pool.

Then you can execute a query:

```js
const result = await pool.query(
  "SELECT * FROM users"
);
```

The pool manages the connection needed for that query.

You don't normally need to manually perform:

```text
Acquire
Query
Release
```

when using `pool.query()` for a standalone query—the pool abstraction handles that lifecycle for you.

---

# 4.14 When You Need Direct Connection Control

Sometimes you need to explicitly acquire a connection.

For example:

```js
const client = await pool.connect();

try {
  await client.query("BEGIN");

  // multiple queries

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Here you're explicitly doing:

```text
pool.connect()
      ↓
Acquire connection
      ↓
Use connection
      ↓
Release connection
```

This becomes particularly important for **transactions**.

We'll cover this in detail later.

---

# 4.15 Why Release Is Not the Same as Close

This is one of the most important concepts to remember.

When using a pool:

```js
client.release();
```

usually means:

> "I'm finished using this connection. Return it to the pool."

It does **not** normally mean:

> "Destroy the PostgreSQL connection."

So:

```text
release()
   ↓
Connection → Pool → Available for reuse
```

whereas:

```text
end()
   ↓
Pool/client shuts down
   ↓
Connections close
```

This distinction becomes critical when we discuss **connection leaks**.

---

# 4.16 Connection Pooling in One Diagram

Here's the complete mental model:

```text
                         Node.js Application
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ Connection Pool │
                         └────────┬────────┘
                                  │
                ┌─────────────────┼─────────────────┐
                │                 │                 │
                ▼                 ▼                 ▼
             Conn 1            Conn 2            Conn 3
             Idle              Busy              Idle
                                  │
                                  ▼
                             PostgreSQL
                                  │
                                  ▼
                              SQL Query
```

When the query finishes:

```text
Conn 2
  ↓
Release
  ↓
Pool
  ↓
Idle
```

Another request can then use it.

---

# 4.17 The Core Mental Model

If you want one sentence for your notes:

> **Connection pooling is the practice of maintaining a controlled collection of reusable PostgreSQL connections and temporarily assigning those connections to database operations as needed.**

And the lifecycle is:

```text
              ┌──────────────┐
              │     Pool     │
              └──────┬───────┘
                     │
                  Acquire
                     ↓
              ┌──────────────┐
              │  Connection  │
              └──────┬───────┘
                     │
                   Query
                     ↓
              ┌──────────────┐
              │   Database   │
              └──────┬───────┘
                     │
                  Release
                     ↓
              ┌──────────────┐
              │     Pool     │
              └──────────────┘
```

### Remember

```text
Pool
 │
 ├── Idle connections
 ├── Busy connections
 └── Waiting operations
```

**Acquire → Use → Release → Reuse**

That is the core of PostgreSQL connection pooling.

---

## 5. How a Connection Pool Works Internally

Next we'll go one level deeper: **how the pool decides whether to reuse an idle connection, create a new one, make an operation wait, or eventually reject it**. This is where the pool starts making sense as an actual piece of backend infrastructure rather than just a `new Pool()` configuration.

# 5. How a Connection Pool Works Internally

Now we're getting into the part that will make the `Pool` abstraction **click**.

You don't need to know the exact source code implementation of `pg.Pool`, but you should understand the **logic a connection pool follows internally**.

The core question is:

> **When my application needs a PostgreSQL connection, what does the pool actually do?**

---

## 5.1 The Pool Maintains a Set of Connections

Conceptually, imagine:

```text
                 Connection Pool
              ┌───────────────────┐
              │                   │
              │ C1 → Idle        │
              │ C2 → Idle        │
              │ C3 → Busy        │
              │ C4 → Idle        │
              │                   │
              └───────────────────┘
```

The pool keeps track of:

* which connections exist
* which connections are idle
* which connections are currently checked out
* which operations are waiting
* how many connections are allowed
* whether connections are still healthy

The actual implementation has more details, but this is the mental model you need.

---

# 5.2 An Application Requests a Connection

Suppose your application needs to execute a query.

Conceptually:

```text
Request
   ↓
"I need a PostgreSQL connection"
   ↓
Pool
```

The pool now has to make a decision.

It essentially asks:

```text
Is an idle connection available?
```

There are three important possibilities.

---

# 5.3 Case 1 — An Idle Connection Exists

Suppose:

```text
Pool
 ├── C1 → Idle
 ├── C2 → Busy
 └── C3 → Idle
```

A request arrives.

The pool can give the operation an idle connection:

```text
Request
   ↓
 Pool
   ↓
 C1
```

Now:

```text
Pool
 ├── C1 → Busy
 ├── C2 → Busy
 └── C3 → Idle
```

The query executes using C1.

When the operation finishes:

```text
C1
 ↓
Release
 ↓
Pool
```

and C1 becomes idle again.

```text
Pool
 ├── C1 → Idle
 ├── C2 → Busy
 └── C3 → Idle
```

### The important point

**The connection wasn't recreated.**

It was reused.

---

# 5.4 Case 2 — No Idle Connection, But Pool Can Create Another

Now imagine:

```text
max = 5
```

Current state:

```text
Pool
 ├── C1 → Busy
 ├── C2 → Busy
 └── C3 → Busy
```

There is no idle connection.

But the pool currently has only three connections:

```text
Current connections = 3
Maximum = 5
```

So the pool can potentially create another connection.

```text
Request
   ↓
 Pool
   ↓
No idle connection
   ↓
Pool below maximum
   ↓
Create C4
   ↓
Request uses C4
```

Now:

```text
Pool
 ├── C1 → Busy
 ├── C2 → Busy
 ├── C3 → Busy
 └── C4 → Busy
```

This is how pools can **grow according to demand**, subject to their configuration and implementation.

---

# 5.5 Case 3 — Pool Is at Maximum Capacity

Now suppose:

```text
max = 4
```

and:

```text
Pool
 ├── C1 → Busy
 ├── C2 → Busy
 ├── C3 → Busy
 └── C4 → Busy
```

There are:

```text
0 idle connections
```

and:

```text
current connections = maximum connections
```

The pool cannot simply keep creating connections indefinitely.

So what happens to another database operation?

```text
Request E
    ↓
  Pool
    ↓
No idle connection
    ↓
Pool already at maximum
    ↓
Wait
```

The operation waits for a connection to become available, subject to the pool/client's timeout behaviour.

---

# 5.6 Waiting Requests

Imagine:

```text
Pool max = 3
```

and:

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

Now:

```text
Request D → Waiting
Request E → Waiting
Request F → Waiting
```

Conceptually:

```text
                 Pool
                  │
          ┌───────┼───────┐
          ↓       ↓       ↓
         C1      C2      C3
        Busy    Busy    Busy
          │       │       │
          └───────┼───────┘
                  │
             Wait Queue
              ├── D
              ├── E
              └── F
```

When one connection becomes available:

```text
C1 finishes
   ↓
C1 becomes available
   ↓
Waiting operation gets C1
```

Conceptually:

```text
C1 → Request D
```

Then:

```text
Request D finishes
   ↓
C1 → Pool
   ↓
Request E can use C1
```

The exact queueing/fairness behaviour is implementation-specific, so don't treat the diagram as a promise of strict FIFO ordering.

---

# 5.7 The Pool Is a Resource Scheduler

At this point, think of the pool as a small resource-management system.

It manages:

```text
Connections
     +
Requests waiting for connections
     +
Connection limits
     +
Connection lifecycle
```

Conceptually:

```text
                ┌─────────────────┐
Requests ──────►│                 │
                │      POOL       │
                │                 │
                │  Connection     │
                │  Management     │
                └────────┬────────┘
                         │
              ┌──────────┼──────────┐
              ↓          ↓          ↓
             C1         C2         C3
```

This is why a pool is much more than an array containing connections.

---

# 5.8 Acquire

When an operation needs a connection, it performs an **acquire** operation.

Conceptually:

```text
Acquire
   ↓
Pool finds available connection
   ↓
Connection checked out
```

In Node.js with `pg`:

```js
const client = await pool.connect();
```

The important part is:

```js
pool.connect()
```

It means:

> "Give me a connection from this pool."

It doesn't necessarily mean:

> "Create a brand-new PostgreSQL connection."

The pool decides whether an existing connection can be reused or whether a new one needs to be established.

---

# 5.9 Use

Once acquired:

```js
const client = await pool.connect();

await client.query("SELECT * FROM users");
```

The application is using that specific connection.

Conceptually:

```text
Pool
  ↓
C2
  ↓
Your code
  ↓
PostgreSQL
```

The connection is considered checked out/busy during this period.

---

# 5.10 Release

When you're finished:

```js
client.release();
```

This tells the pool:

> "I'm finished with this connection. You can make it available for reuse."

Conceptually:

```text
C2
 ↓
release()
 ↓
Pool
 ↓
Idle
```

Again:

```text
release()
```

is generally **not**:

```text
close PostgreSQL connection
```

It's:

```text
return connection to pool
```

---

# 5.11 Reuse

Now another request arrives:

```text
Request B
    ↓
Pool
    ↓
C2
```

The pool can reuse the same connection.

Therefore:

```text
C2
 │
 ├── Request A
 ├── Request B
 ├── Request F
 └── Request K
```

over the lifetime of the application.

That's the primary reason pooling saves connection-establishment overhead.

---

# 5.12 What If a Connection Becomes Unhealthy?

Connections don't live forever under all circumstances.

For example, a network failure could occur:

```text
Node.js
   │
   X
   │
PostgreSQL
```

or the database server could restart.

An existing connection might therefore become unusable.

A properly implemented pool/client library can detect certain connection failures and remove/discard broken connections rather than repeatedly handing the same broken connection to application code.

Conceptually:

```text
Pool
 ├── C1 → Healthy
 ├── C2 → Healthy
 ├── C3 → Broken
 └── C4 → Healthy
```

The broken connection is removed and, when appropriate, the pool can establish a replacement.

The exact detection and replacement behaviour depends on the client library.

---

# 5.13 The Pool Can Grow and Shrink

A pool doesn't necessarily remain at one fixed number of connections forever.

You might configure:

```text
max = 10
```

but currently have:

```text
3 connections
```

Later, demand increases:

```text
3 → 4 → 5 → 6
```

Eventually it could reach:

```text
10
```

if demand requires it and the pool creates connections accordingly.

Similarly, when connections become idle, the pool may eventually close some connections depending on its configuration and idle-management behaviour.

So distinguish:

```text
Maximum pool size
```

from:

```text
Current pool size
```

They are not the same thing.

---

# 5.14 `max` Is a Ceiling, Not a Target

This is extremely important.

Suppose:

```js
const pool = new Pool({
  max: 20
});
```

Don't interpret this as:

> "Create 20 connections."

Interpret it as:

> "The pool is allowed to maintain up to 20 connections."

Conceptually:

```text
max = 20

Current:
3 connections

Could grow:
3 → 4 → 5 → ... → 20
```

The actual connection creation behaviour depends on demand and pool configuration.

---

# 5.15 Pool State Over Time

Let's watch a pool during traffic.

### Initial state

```text
Pool
 └── No/limited connections
```

### Request A

```text
Request A
   ↓
Pool
   ↓
Create C1
   ↓
C1 → Busy
```

### Request A finishes

```text
C1 → Idle
```

### Request B

```text
Request B
   ↓
Pool
   ↓
Reuse C1
```

No new connection is needed.

### Requests B, C, D arrive together

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

The pool may create additional connections to satisfy demand.

### More requests arrive

```text
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

If:

```text
max = 5
```

then another operation may need to wait.

### Connection becomes available

```text
C2 → Idle
```

A waiting operation can now acquire C2.

This dynamic behaviour is the heart of pooling.

---

# 5.16 A Complete Example

Suppose:

```text
max = 3
```

Three requests arrive:

```text
Request A ──→ C1
Request B ──→ C2
Request C ──→ C3
```

Now:

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

Request D arrives:

```text
Request D
    ↓
Pool
    ↓
No available connection
    ↓
Waiting
```

Then Request A finishes:

```text
Request A
    ↓
C1
    ↓
Release
```

Now:

```text
C1 → Available
```

Request D gets it:

```text
Request D → C1
```

After D finishes:

```text
C1 → Pool
```

The same connection has served multiple requests:

```text
C1
 │
 ├── Request A
 └── Request D
```

No unnecessary connection creation occurred between those operations.

---

# 5.17 `pool.query()` Simplifies This

For a simple standalone query, you can write:

```js
const result = await pool.query(
  "SELECT * FROM users"
);
```

You don't manually write:

```text
Acquire
↓
Query
↓
Release
```

The pool abstraction handles the necessary connection management.

Conceptually:

```text
pool.query()
    ↓
Acquire connection
    ↓
Execute query
    ↓
Return connection
    ↓
Return result
```

This is one reason `pool.query()` is convenient for independent queries.

---

# 5.18 `pool.connect()` Gives You a Specific Connection

When you do:

```js
const client = await pool.connect();
```

you're explicitly obtaining a connection.

Now **you are responsible for releasing it**:

```js
client.release();
```

Typical pattern:

```js
const client = await pool.connect();

try {
  const result = await client.query(
    "SELECT * FROM users"
  );

  return result.rows;
} finally {
  client.release();
}
```

The `finally` block is important because the connection should be released even when the query throws an error.

---

# 5.19 Why This Matters for Transactions

This becomes particularly important with transactions.

A transaction consists of multiple statements that need to execute within the same database session/connection:

```text
Connection C1
     │
     ├── BEGIN
     ├── Query 1
     ├── Query 2
     ├── Query 3
     └── COMMIT
```

Therefore, you typically acquire one pool connection:

```js
const client = await pool.connect();
```

and keep that same connection throughout the transaction.

We'll cover this deeply later.

For now, remember:

> **Standalone query → `pool.query()` is often enough.**

> **Multiple operations that must share one connection, especially a transaction → explicitly acquire a client with `pool.connect()`.**

---

# 5.20 The Internal Mental Model

Put this diagram in your notes:

```text
                         Application
                              │
                         Request for DB
                              │
                              ▼
                    ┌──────────────────┐
                    │      POOL        │
                    │                  │
                    │ Idle connections │
                    │ Busy connections │
                    │ Waiting requests │
                    │ Max connection   │
                    │ configuration    │
                    └────────┬─────────┘
                             │
               ┌─────────────┼─────────────┐
               ↓             ↓             ↓
              C1            C2            C3
             Idle           Busy          Busy
               │                           │
               └──────────────┬────────────┘
                              │
                         PostgreSQL
```

When a request needs a connection:

```text
Request
   ↓
Pool
   │
   ├── Idle available?
   │       ↓ Yes
   │    Give it out
   │
   ├── No idle?
   │       ↓
   │    Below max?
   │       ↓ Yes
   │    Create connection
   │
   └── At max?
           ↓
        Wait / timeout
```

That's the basic decision-making model.

---

# Key Takeaways

### 1. The pool manages connections

```text
Pool
 ├── Connections
 ├── Idle state
 ├── Busy state
 └── Waiting operations
```

### 2. The normal lifecycle is

```text
Acquire
   ↓
Use
   ↓
Release
   ↓
Reuse
```

### 3. When a connection is needed

The pool generally tries to:

```text
1. Reuse an idle connection
2. Create a new connection if allowed and needed
3. Otherwise make the operation wait
```

subject to the pool implementation and timeout configuration.

### 4. `max` is a ceiling

```text
max = 10
```

doesn't necessarily mean:

```text
10 connections immediately
```

It means the pool can maintain up to that configured maximum.

### 5. `release()` ≠ close

```text
client.release()
```

normally means:

```text
Return connection → Pool
```

not:

```text
Destroy connection
```

### 6. `pool.query()` vs `pool.connect()`

```text
pool.query()
    ↓
Convenient for independent queries
    ↓
Pool manages acquisition/release
```

Whereas:

```text
pool.connect()
    ↓
You explicitly obtain a connection
    ↓
You use it
    ↓
You must release it
```

### Core mental model

> **A connection pool is a resource manager. It maintains a bounded collection of reusable PostgreSQL connections, gives available connections to database operations, creates new connections when permitted, makes operations wait when the pool is exhausted, and returns connections to the pool for reuse.**

---

# 6. Connection Lifecycle

Next, we'll zoom in on the **complete lifecycle of one PostgreSQL connection inside a pool**:

```text
Create
  ↓
Connect
  ↓
Idle
  ↓
Acquire
  ↓
Busy
  ↓
Release
  ↓
Idle
  ↓
Reuse
  ↓
Eventually close
```

This section is especially important because it sets us up for **timeouts, idle connections, connection leaks, transactions, and graceful shutdown**.

# 6. Connection Lifecycle

Now let's follow **one PostgreSQL connection** from the moment the pool creates it until the moment that connection is finally closed.

This is important because a connection doesn't simply follow:

```text
Create → Query → Destroy
```

With pooling, its lifecycle is more like:

```text
Create
  ↓
Connect
  ↓
Idle
  ↓
Acquire
  ↓
Busy
  ↓
Release
  ↓
Idle
  ↓
Acquire again
  ↓
Busy
  ↓
...
  ↓
Close
```

The same connection can go through this cycle many times.

---

# 6.1 Connection Lifecycle at a High Level

A pooled PostgreSQL connection can be thought of as having these stages:

```text
1. Creation
      ↓
2. Connection establishment
      ↓
3. Idle
      ↓
4. Acquisition
      ↓
5. In use
      ↓
6. Release
      ↓
7. Idle again
      ↓
8. Reuse
      ↓
9. Eventually closed
```

Let's understand each stage.

---

# 6.2 Stage 1 — Connection Creation

Initially, the pool may need a new PostgreSQL connection.

For example:

```text id="t4x0cx"
Application
     ↓
Connection Pool
     ↓
Create connection
```

The pool/client library creates the client-side connection object and begins establishing communication with PostgreSQL.

This isn't necessarily the same as the application manually saying:

```js
new Client()
```

for every request.

The pool handles connection creation as part of its own lifecycle.

---

# 6.3 Stage 2 — Connection Establishment

The new connection establishes communication with PostgreSQL.

Conceptually:

```text id="sqy69m"
Pool
 ↓
TCP connection
 ↓
PostgreSQL
 ↓
Authentication
 ↓
Session established
```

Once successful:

```text id="4h3trb"
Connection
     ↓
Ready
```

The connection can now be used for SQL operations.

---

# 6.4 Stage 3 — Idle

If the pool created the connection but no operation currently needs it, the connection becomes **idle**.

```text id="fz0n7u"
Pool
 ├── C1 → Idle
 ├── C2 → Idle
 └── C3 → Idle
```

An idle connection is:

> A healthy connection that belongs to the pool but is currently not checked out for application work.

This does **not** mean the connection is closed.

It remains available for reuse.

---

# 6.5 Idle Does Not Mean Disconnected

This distinction is important.

When:

```text id="cjq7t4"
C1 → Idle
```

it does **not** normally mean:

```text id="u3j2h7"
C1 → Disconnected
```

Instead:

```text id="pmyj8k"
C1 → PostgreSQL
     │
     └── Connection remains established
```

The purpose of keeping it idle is precisely so it can be reused without establishing a new connection.

---

# 6.6 Stage 4 — Acquisition

Now an application operation needs a database connection.

For example:

```js id="yq5cwb"
const client = await pool.connect();
```

The pool looks for an available connection.

Suppose:

```text id="1n9swt"
C1 → Idle
C2 → Busy
C3 → Idle
```

The pool can give C1 to the operation:

```text id="k3yqhc"
Request
   ↓
Pool
   ↓
C1
```

C1 is now **checked out**.

---

# 6.7 Stage 5 — Connection Is Busy

While your application is using the acquired connection:

```text id="t5w1zj"
C1 → Busy
```

For example:

```js id="j2f7d8"
const client = await pool.connect();

const result = await client.query(
  "SELECT * FROM users"
);
```

Conceptually:

```text id="h9b9s4"
Application
    ↓
C1
    ↓
PostgreSQL
```

The connection is temporarily assigned to that operation.

---

# 6.8 A Connection Can Execute Multiple Queries

A connection doesn't necessarily become idle after every SQL statement.

Suppose:

```js id="xg6k3f"
const client = await pool.connect();

await client.query("SELECT ...");
await client.query("UPDATE ...");
await client.query("INSERT ...");

client.release();
```

The lifecycle is:

```text id="4h9qwr"
Acquire C1
    ↓
Query 1
    ↓
Query 2
    ↓
Query 3
    ↓
Release C1
```

C1 remains checked out throughout that period.

This becomes particularly important for transactions.

---

# 6.9 Stage 6 — Release

Once your application is finished with the connection:

```js id="e6o1s5"
client.release();
```

The connection goes back to the pool.

```text id="y3h8uk"
Busy
  ↓
release()
  ↓
Idle
```

Conceptually:

```text id="ny6nza"
Application
     ↓
client.release()
     ↓
Connection Pool
     ↓
C1 → Idle
```

Again:

> **Release means return the connection to the pool.**

It doesn't normally mean destroy the underlying PostgreSQL connection.

---

# 6.10 Why Release Is So Important

Imagine:

```text id="qz8z7w"
Pool max = 5
```

Your application acquires five connections:

```text id="j8m1v9"
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

Now another request needs a connection:

```text id="tqf8hp"
Request F
    ↓
Pool
    ↓
No available connection
    ↓
Wait
```

If your application eventually releases C1:

```text id="sv6q9b"
C1 → Idle
```

Request F can use it.

But if your application **forgets to release connections**, the pool can become exhausted.

We'll dedicate an entire later section to this problem:

**Connection Leaks.**

---

# 6.11 Stage 7 — Idle Again

After release:

```text id="j7n6fn"
C1 → Idle
```

The connection remains inside the pool.

Now another request can acquire it:

```text id="19r5fk"
Request B
    ↓
Pool
    ↓
C1
```

No new PostgreSQL connection needs to be established merely because another request arrived.

---

# 6.12 Stage 8 — Connection Reuse

This is the key benefit of pooling.

The same connection can repeatedly transition between:

```text id="2w6w0f"
Idle
 ↓
Busy
 ↓
Idle
 ↓
Busy
 ↓
Idle
 ↓
Busy
 ↓
...
```

For example:

```text id="9m5c1p"
C1

Request A
   ↓
Busy
   ↓
Idle

Request B
   ↓
Busy
   ↓
Idle

Request C
   ↓
Busy
   ↓
Idle
```

One connection can serve many operations over its lifetime.

---

# 6.13 Stage 9 — Eventually the Connection Closes

A pooled connection doesn't necessarily remain open forever.

It can eventually be closed for various reasons.

For example:

* application shuts down
* pool is shut down
* connection becomes unusable
* idle connection-management policy closes it
* connection reaches a configured lifetime/expiration policy, if applicable
* database/network failure occurs

Conceptually:

```text id="y0k4o3"
Idle
  ↓
Pool decides connection should close
  ↓
Connection closed
```

The exact behaviour depends on the pool/client configuration and environment.

---

# 6.14 `pool.end()`

When your Node.js application is shutting down, you can close the pool:

```js id="k5x5ko"
await pool.end();
```

Conceptually:

```text id="6zj9z8"
Application shutting down
          ↓
      pool.end()
          ↓
Close pool
          ↓
Close its PostgreSQL connections
```

This is different from:

```js id="8v0d4b"
client.release();
```

Compare:

```text id="c5f4a2"
client.release()
      ↓
Return ONE connection
to the pool
```

with:

```text id="9m7h0w"
pool.end()
      ↓
Shut down the pool
and close its connections
```

This distinction is **critical**.

---

# 6.15 Complete Lifecycle Diagram

Put this in your README:

```text id="w8c0n8"
                 Connection Pool
                       │
                       │ Create
                       ▼
              ┌─────────────────┐
              │   Connecting     │
              └────────┬────────┘
                       │
                 Connection OK
                       │
                       ▼
              ┌─────────────────┐
              │      IDLE       │◄──────────────┐
              └────────┬────────┘               │
                       │                        │
                    Acquire                     │
                       │                        │
                       ▼                        │
              ┌─────────────────┐               │
              │      BUSY       │               │
              └────────┬────────┘               │
                       │                        │
                    Release                     │
                       │                        │
                       └────────────────────────┘

                       Eventually
                       │
                       ▼
              ┌─────────────────┐
              │     CLOSED      │
              └─────────────────┘
```

The most common path is:

```text id="9n7e0y"
Create
  ↓
Connect
  ↓
Idle
  ↓
Acquire
  ↓
Busy
  ↓
Release
  ↓
Idle
  ↓
Acquire again
  ↓
Busy
  ↓
Release
  ↓
...
```

---

# 6.16 Lifecycle During a Normal API Request

Let's connect this to your Node.js backend.

Suppose:

```text id="x42u8s"
GET /users
```

Your application does:

```js id="2ey2lz"
const result = await pool.query(
  "SELECT * FROM users"
);
```

Conceptually:

```text id="d9f2v4"
HTTP Request
     ↓
pool.query()
     ↓
Pool finds idle connection
     ↓
Connection acquired
     ↓
SQL executed
     ↓
Connection returned to pool
     ↓
Result returned
     ↓
HTTP Response
```

Notice something important:

The **HTTP request ends**, but the PostgreSQL connection doesn't necessarily end.

```text id="7j6x6g"
HTTP Request
    ↓
Database query
    ↓
HTTP Response

Connection
    ↓
Returned to pool
    ↓
Still available
```

This is one of the biggest conceptual differences between HTTP request lifecycle and database connection lifecycle.

---

# 6.17 HTTP Request ≠ Database Connection

Don't mentally tie these together:

```text id="s3v2lf"
1 HTTP request
      ≠
1 PostgreSQL connection
```

Instead:

```text id="j72u6w"
Many HTTP requests
        ↓
    Connection Pool
        ↓
Limited set of PostgreSQL connections
```

For example:

```text id="b8c8ii"
100 HTTP requests
       ↓
   Pool max = 10
       ↓
Up to roughly 10 pool connections
being used concurrently
```

The exact behaviour depends on the workload and client implementation, but the important idea is that **HTTP concurrency and database connection count are separate concepts**.

---

# 6.18 Lifecycle During a Transaction

This is where lifecycle becomes even more important.

Suppose:

```text id="4hr5ha"
Transaction
```

The application acquires a connection:

```text id="7p7yqy"
Pool
 ↓
C1
 ↓
BEGIN
```

Then:

```text id="1d9gzk"
C1
 │
 ├── BEGIN
 ├── Query 1
 ├── Query 2
 ├── Query 3
 └── COMMIT
```

Only after the transaction finishes should the application release the connection:

```text id="6v8l3n"
COMMIT
  ↓
release()
  ↓
C1 → Idle
```

You don't want to release C1 halfway through the transaction.

Why?

Because transaction state belongs to the connection/session.

We'll go much deeper into this in the **Transactions + Pooling** section.

---

# 6.19 What If an Error Happens?

Consider:

```js id="0udlqd"
const client = await pool.connect();

try {
  await client.query("SELECT ...");
} catch (error) {
  console.error(error);
} finally {
  client.release();
}
```

The important part is:

```js id="5qk0jx"
finally {
  client.release();
}
```

Whether the query succeeds or fails, your application gets a chance to return the connection to the pool.

The lifecycle should therefore be:

```text id="k8o6qa"
Acquire
   ↓
Try operation
   ↓
Success ──────┐
              │
Error ────────┤
              ↓
           Release
              ↓
             Pool
```

This pattern is fundamental when manually acquiring connections.

---

# 6.20 Connection Lifecycle vs Pool Lifecycle

Don't confuse these two.

### Individual connection lifecycle

```text id="7y5q7c"
Create
 ↓
Connect
 ↓
Idle
 ↓
Acquire
 ↓
Busy
 ↓
Release
 ↓
Idle
 ↓
...
 ↓
Close
```

### Pool lifecycle

```text id="2zv3pi"
Create Pool
    ↓
Manage Connections
    ↓
Serve Requests
    ↓
Create/Reuse Connections
    ↓
Shutdown
    ↓
pool.end()
```

The pool can manage many individual connection lifecycles.

```text id="l0d0cb"
              Pool
        ┌───────┼───────┐
        ↓       ↓       ↓
       C1      C2      C3
        │       │       │
     lifecycle lifecycle lifecycle
```

---

# 6.21 The Most Important Distinctions

### `release()`

```text
client.release()
```

Means:

> I'm finished using this connection. Return it to the pool.

### `pool.end()`

```text
await pool.end()
```

Means:

> Shut down the pool and close its connections.

### `client.end()`

With a directly created `pg.Client`, this closes that client's connection.

It's conceptually different from releasing a pooled client.

---

# Key Takeaways

### Connection lifecycle

```text id="yp7z2q"
Create
  ↓
Connect
  ↓
Idle
  ↓
Acquire
  ↓
Busy
  ↓
Release
  ↓
Idle
  ↓
Reuse
  ↓
...
  ↓
Close
```

### Remember:

* A pool manages the lifecycle of multiple connections.
* A connection can be reused many times.
* **Idle does not mean disconnected.**
* **Acquire** takes a connection from the pool for use.
* **Busy** means the connection is currently checked out.
* **Release** returns the connection to the pool.
* **Release does not normally destroy the connection.**
* `pool.end()` shuts down the pool and closes its connections.
* HTTP request lifecycle and database connection lifecycle are different.
* A connection can survive long after the HTTP request that used it has finished.
* Transactions require keeping the same connection for the duration of the transaction.
* When manually acquiring connections, always ensure they are released—even when errors occur.

### Core mental model

> **A pooled PostgreSQL connection is a reusable resource. It is created and connected once, spends much of its life idle in the pool, is temporarily acquired for database work, released back to the pool, reused by later operations, and eventually closed when the pool or connection determines it should be shut down.**

---

# 7. Connection Pool Terminology

Next we'll build your **pooling vocabulary** properly: `idle`, `active/busy`, `acquire`, `release`, `max`, `min`, wait queue, checkout, check-in, timeouts, and connection lifetime. Once these terms are clear, PostgreSQL/Node.js documentation becomes *much* easier to read.

# 7. Connection Pool Terminology

Connection pooling has a small vocabulary that you'll see repeatedly in PostgreSQL documentation, Node.js libraries, production logs, and backend architecture discussions.

If these terms become second nature, connection-pooling configuration will become much easier to understand.

---

# 7.1 Pool

A **pool** is a manager that maintains and manages a collection of database connections.

```text id="2b8d9e"
              Connection Pool
        ┌────────────────────────┐
        │ C1  C2  C3  C4  C5    │
        └────────────────────────┘
```

The pool is responsible for managing those connections and making them available to application operations.

With Node.js and the `pg` library:

```js id="l0j8yq"
const pool = new Pool({
  max: 10
});
```

Think:

> **Pool = connection manager**

---

# 7.2 Connection

A **connection** is an established communication/session between your application and PostgreSQL.

```text id="w3o5px"
Node.js
   │
   │ Connection
   ▼
PostgreSQL
```

A pool contains multiple connections:

```text id="l7aq72"
Pool
 ├── Connection 1
 ├── Connection 2
 ├── Connection 3
 └── Connection 4
```

---

# 7.3 Idle Connection

An **idle connection** is a connection that currently belongs to the pool but isn't being used by an application operation.

```text id="x0j6sc"
Pool
 ├── C1 → Idle
 ├── C2 → Busy
 └── C3 → Idle
```

An idle connection is generally still connected to PostgreSQL.

That's the entire point:

```text id="iy5gq4"
Idle
 ↓
Already connected
 ↓
Ready for reuse
```

So:

> **Idle ≠ disconnected**

---

# 7.4 Active / Busy Connection

A **busy** connection is currently checked out and being used by application code.

```text id="1c9z1s"
Request A
    ↓
   C1
    ↓
PostgreSQL
```

The pool might look like:

```text id="m2j7ab"
C1 → Busy
C2 → Idle
C3 → Idle
```

Once the operation is finished, the application can release C1.

---

# 7.5 Acquire

**Acquire** means obtaining a connection from the pool for use.

For example:

```js id="y7u7gn"
const client = await pool.connect();
```

Conceptually:

```text id="a0j9qf"
Application
    ↓
Acquire
    ↓
Pool
    ↓
Connection
```

You are essentially saying:

> "Give me a connection that I can use."

The pool decides which suitable connection to provide or whether the request needs to wait/create a connection.

---

# 7.6 Checkout

**Checkout** is another term for taking a connection out of the pool's available/idle set for use.

```text id="7j0y8w"
Idle
 ↓
Checkout
 ↓
Busy
```

You may hear:

> "The application checked out a connection."

That's conceptually the same operation as acquiring a connection.

---

# 7.7 Release

**Release** means returning an acquired connection to the pool.

```js id="pl4b8p"
client.release();
```

Conceptually:

```text id="0w8kqa"
Busy
 ↓
Release
 ↓
Idle
```

Remember:

```text id="g8j9f1"
release()
    ≠
close()
```

Usually:

```text id="k0n4c7"
release()
   ↓
Return connection to pool
```

not:

```text id="6d1fsl"
release()
   ↓
Destroy connection
```

---

# 7.8 Check-in

**Check-in** is another term for returning a connection to the pool.

So:

```text id="l4jvnp"
Checkout → Acquire
Check-in → Release
```

You don't necessarily need to use these terms in your code, but you'll encounter them in database documentation and discussions.

---

# 7.9 Pool Size

**Pool size** generally refers to how many connections the pool maintains or is allowed to maintain, depending on context.

For example:

```js id="o8fd9c"
const pool = new Pool({
  max: 10
});
```

Here:

```text id="l3p0b7"
max = 10
```

sets the maximum number of connections that this pool can use.

Be careful when someone says:

> "The pool has 10 connections."

They may mean:

* maximum configured size
* current number of connections
* currently active connections

Those are different measurements.

---

# 7.10 Maximum Pool Size — `max`

In `node-postgres` (`pg`), the option is:

```js id="2m0jsk"
max
```

For example:

```js id="k0j5h1"
const pool = new Pool({
  max: 10
});
```

This establishes an upper bound on the number of clients/connections in that pool.

Conceptually:

```text id="q4w0g6"
max = 10

C1
C2
C3
...
C10
```

The pool doesn't necessarily create all ten immediately.

Think of `max` as:

> **The ceiling on the pool's connection count.**

---

# 7.11 Minimum Pool Size — `min`

Some pool implementations provide a minimum pool size configuration.

Conceptually:

```text id="s3t4x0"
min = 2
max = 10
```

means the pool aims to maintain at least a configured baseline number of connections, while allowing the pool to grow up to its maximum as needed.

However, **don't assume every PostgreSQL pooling library behaves identically**, and don't confuse `min` with "exactly this many connections will always be doing useful work."

For `pg`, the commonly important pool-size setting is `max`; other client/pool libraries may expose different options.

---

# 7.12 Current Connections

This means how many connections the pool currently has.

For example:

```text id="s1w3ri"
max = 10

Current = 4
```

The pool currently has four connections, even though it is allowed to have up to ten.

```text id="2ad5aj"
Pool
 ├── C1
 ├── C2
 ├── C3
 └── C4
```

So:

```text id="5obv7w"
Current connections ≠ Maximum connections
```

---

# 7.13 Idle Connections

This means how many existing pool connections are currently available.

Example:

```text id="n7nyu6"
Current = 5

C1 → Idle
C2 → Idle
C3 → Busy
C4 → Busy
C5 → Idle
```

Therefore:

```text id="hkw3d8"
Idle = 3
Busy = 2
```

Conceptually:

```text id="uh9t8k"
Current connections
        │
        ├── Idle
        └── Busy
```

---

# 7.14 Waiting Requests

A **waiting request** is a database operation waiting for a connection to become available.

Example:

```text id="0x9q4q"
max = 3

C1 → Busy
C2 → Busy
C3 → Busy
```

Now:

```text id="d6q3xj"
Request D → Waiting
Request E → Waiting
```

The pool cannot immediately give them a connection.

They wait until an available connection exists, or until the relevant timeout/error condition occurs.

---

# 7.15 Wait Queue

The collection of operations waiting for a connection can be thought of as a **wait queue**.

```text id="7z6l9q"
             Pool
              │
       ┌──────┼──────┐
       ↓      ↓      ↓
      C1     C2     C3
     Busy   Busy   Busy
                     │
                     ▼
                 Wait Queue
                  ├── Req D
                  ├── Req E
                  └── Req F
```

The exact queue implementation and ordering are library-specific, so don't assume strict FIFO unless the documentation says so.

---

# 7.16 Pool Exhaustion

**Pool exhaustion** occurs when all available connections are in use and the pool has reached its configured maximum.

Example:

```text id="4oxzj8"
max = 5

C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

There are:

```text id="x2m7k3"
0 idle connections
```

and:

```text id="j3n4pk"
Current = max
```

A new operation cannot immediately obtain a connection.

It must wait or eventually fail depending on the configured timeout/behaviour.

---

# 7.17 Connection Leak

A **connection leak** happens when application code acquires a pooled connection but fails to return it to the pool.

For example:

```js id="j8m4op"
const client = await pool.connect();

await client.query("SELECT ...");

// Forgot client.release()
```

Now:

```text id="z5g8os"
Connection
     ↓
Checked out
     ↓
Never returned
```

If this happens repeatedly:

```text id="2f7r8s"
C1 → Leaked
C2 → Leaked
C3 → Leaked
C4 → Leaked
C5 → Leaked
```

Eventually:

```text id="r2q3ls"
Pool exhausted
```

This is why:

```js id="n9j3pm"
try {
   // database work
} finally {
   client.release();
}
```

is such an important pattern.

We'll dedicate a later section specifically to connection leaks.

---

# 7.18 Connection Timeout

A **connection timeout** generally means an operation doesn't get a usable database connection within an allowed amount of time, or that establishing a connection takes too long.

Be careful: PostgreSQL clients can expose **different timeout settings for different stages**.

For example:

```text id="3s1z9f"
Waiting for pool connection
        ≠
Establishing TCP connection
        ≠
Waiting for PostgreSQL response
```

These are separate concepts.

We'll cover the different timeout categories later.

---

# 7.19 Idle Timeout

An **idle timeout** controls how long an unused connection can remain idle before the pool may close it, depending on the pool implementation.

Conceptually:

```text id="8v6r5c"
Connection
    ↓
Idle
    ↓
Idle for too long
    ↓
Close
```

This can help prevent a pool from keeping unnecessary idle connections indefinitely.

The exact semantics depend on the library.

---

# 7.20 Connection Lifetime / Maximum Lifetime

Some pooling systems support a maximum lifetime for connections.

Conceptually:

```text id="3q2s2q"
Connection created
       ↓
Used
       ↓
Released
       ↓
Reused
       ↓
...
       ↓
Maximum lifetime reached
       ↓
Connection closed/replaced
```

This can be useful in long-running production systems.

Again, whether and how this is supported depends on the specific pool/client library.

---

# 7.21 `pool.query()`

With `pg`:

```js id="l5q6qv"
const result = await pool.query(
  "SELECT * FROM users"
);
```

This is the convenient path for a standalone query.

Conceptually:

```text id="4t9z3a"
pool.query()
     ↓
Acquire connection
     ↓
Execute query
     ↓
Release connection
     ↓
Return result
```

You don't manually manage the connection for this simple use case.

---

# 7.22 `pool.connect()`

This explicitly acquires a pooled client:

```js id="2y4wqx"
const client = await pool.connect();
```

Now your code controls the connection:

```text id="t8h8lj"
Pool
 ↓
client
 ↓
Your code
```

You must eventually:

```js id="x8u4pq"
client.release();
```

This is particularly useful for:

* transactions
* multiple related queries that need the same session
* cases where explicit connection control is required

---

# 7.23 `client.release()`

When a client came from:

```js id="q9n1h7"
pool.connect()
```

you return it using:

```js id="0gl6ad"
client.release();
```

Mental model:

```text id="b4m8yb"
pool.connect()
      ↓
Acquire
      ↓
Use
      ↓
client.release()
      ↓
Pool
```

---

# 7.24 `pool.end()`

This shuts down the pool.

```js id="f7h4h4"
await pool.end();
```

Conceptually:

```text id="zx5q8u"
Pool
 ├── C1
 ├── C2
 └── C3
      ↓
   pool.end()
      ↓
Connections close
      ↓
Pool shuts down
```

This is generally associated with application shutdown, not normal request handling.

---

# 7.25 Pool Utilisation

You may hear people discuss **pool utilisation**.

Conceptually:

```text id="b1g0cf"
Pool max = 10

Busy = 8
Idle = 2
```

That's relatively high utilisation:

```text id="b2u4u8"
8 / 10 = 80%
```

If this remains high under normal traffic, you may need to investigate:

* query duration
* traffic levels
* pool sizing
* database capacity
* application architecture

But **high utilisation alone doesn't automatically mean "increase the pool."**

You need to understand why connections are busy.

---

# 7.26 Pool Saturation

A pool is **saturated** when it is operating at or near its maximum capacity.

Example:

```text id="m0q3z4"
max = 10

Busy = 10
Idle = 0
Waiting = 15
```

This is a strong indication that database access is currently constrained by the pool.

But again, the correct response isn't automatically:

```text id="y4x5q5"
max = 100
```

You first need to determine whether the bottleneck is:

```text id="s4g8r8"
Pool size?
Database?
Slow queries?
Long transactions?
Traffic?
Connection leaks?
```

---

# 7.27 Pool Metrics

In production, you'll often care about metrics such as:

```text id="7v3d1g"
Total connections
Idle connections
Busy connections
Waiting operations
Connection creation rate
Connection errors
Query latency
Pool wait time
```

These metrics help answer questions like:

> "Are requests waiting because we don't have enough database connections?"

or:

> "Are connections staying busy because our queries are slow?"

That distinction is extremely important.

---

# 7.28 Important Vocabulary Table

Here's the compact reference for your README:

| Term                    | Meaning                                                        |
| ----------------------- | -------------------------------------------------------------- |
| **Pool**                | Manager of reusable database connections                       |
| **Connection**          | Communication/session with PostgreSQL                          |
| **Idle**                | Connection available for reuse                                 |
| **Busy / Active**       | Connection currently checked out                               |
| **Acquire**             | Obtain a connection from the pool                              |
| **Checkout**            | Take a connection out for use                                  |
| **Release**             | Return a connection to the pool                                |
| **Check-in**            | Return a connection to the pool                                |
| **Pool size**           | Number of connections maintained/allowed, depending on context |
| **`max`**               | Maximum connections allowed by the `pg` pool                   |
| **Current connections** | Connections currently existing                                 |
| **Waiting**             | Operations waiting for a connection                            |
| **Wait queue**          | Collection of waiting operations                               |
| **Pool exhaustion**     | No available connection and pool is at its limit               |
| **Connection leak**     | Acquired connection that isn't returned                        |
| **Idle timeout**        | Policy for closing idle connections                            |
| **Connection timeout**  | Timeout related to establishing/getting a connection           |
| **Pool utilisation**    | How much of the pool is currently in use                       |
| **Pool saturation**     | Pool operating at/near its connection limit                    |
| **`pool.query()`**      | Convenient pooled query API                                    |
| **`pool.connect()`**    | Explicitly acquire a pooled client                             |
| **`client.release()`**  | Return acquired client to pool                                 |
| **`pool.end()`**        | Shut down the pool                                             |

---

# 7.29 The Vocabulary You Should Memorise

You don't need to memorise every obscure pooling term.

These are the **core ones**:

```text id="j4k1j0"
POOL
  ↓
CONNECTION
  ↓
IDLE
  ↓
BUSY
  ↓
ACQUIRE
  ↓
USE
  ↓
RELEASE
  ↓
IDLE
```

When all connections are busy:

```text id="m0o1n0"
BUSY
BUSY
BUSY
BUSY
BUSY
 ↓
POOL EXHAUSTED
 ↓
WAITING
```

And if your code forgets:

```text id="4nyzj4"
RELEASE
```

you can get:

```text id="2x3xpm"
CONNECTION LEAK
      ↓
POOL EXHAUSTION
      ↓
DATABASE REQUESTS WAIT/FAIL
```

That chain is worth remembering.

---

# Key Takeaways

The most important vocabulary is:

```text id="d5t4po"
Acquire
   ↓
Busy
   ↓
Use
   ↓
Release
   ↓
Idle
   ↓
Reuse
```

And:

```text id="w2j4cc"
max
 ↓
Maximum pool capacity

Current
 ↓
Connections currently existing

Idle
 ↓
Connections available

Busy
 ↓
Connections currently being used

Waiting
 ↓
Operations waiting for a connection
```

Finally:

> **A pool manages connections; connections execute database work; acquire checks a connection out; release returns it; idle connections are reusable; and pool exhaustion occurs when all available connections are busy and the pool cannot create more.**

---

# 8. Pool Size and `max`

Next, we'll focus entirely on **pool sizing**—what `max` really means in `node-postgres`, how it relates to concurrency, why setting it too low or too high can hurt you, and how it interacts with PostgreSQL's own `max_connections`.

This is where the theory starts becoming **real production backend engineering**.

# 8. Pool Size and `max`

Pool size is one of the most important practical parts of connection pooling.

A beginner often sees:

```js
const pool = new Pool({
  max: 10
});
```

and thinks:

> "Okay, my application can handle 10 users."

That's **not** what it means.

Or:

> "PostgreSQL will always have 10 connections."

Also **not necessarily**.

Let's build the correct mental model.

---

# 8.1 What Is Pool Size?

A connection pool maintains a collection of PostgreSQL connections.

The pool size describes how many connections the pool can maintain/use, depending on the specific pool implementation and configuration.

With `node-postgres`:

```js
const pool = new Pool({
  max: 10
});
```

`max` is the **maximum number of clients/connections that this pool can have checked out/maintain**, subject to the library's semantics.

Think of it as a ceiling:

```text
max = 10

          Maximum
             ↓
┌─────────────────────────┐
│ C1 C2 C3 C4 C5 C6 C7   │
│ C8 C9 C10              │
└─────────────────────────┘
```

The pool can have fewer than 10 connections when demand doesn't require more.

---

# 8.2 `max` Is a Ceiling, Not a Target

This distinction is extremely important.

Suppose:

```js
const pool = new Pool({
  max: 20
});
```

It does **not** necessarily mean:

```text
Application starts
      ↓
Create 20 connections
```

Instead, think:

```text
Maximum allowed by pool
          ↓
         20
```

The current number might be:

```text
0
1
2
5
10
...
20
```

depending on workload, configuration, and pool behaviour.

So:

```text
max = maximum capacity
```

not:

```text
max = connections always created
```

---

# 8.3 Current Pool Size vs Maximum Pool Size

These are different concepts.

Suppose:

```text
max = 10
```

but currently:

```text
current connections = 4
```

Then:

```text
Pool
 ├── C1
 ├── C2
 ├── C3
 └── C4
```

The pool is currently using four connections but could grow up to its configured maximum.

```text
Current = 4
Maximum = 10
```

Don't confuse the two.

---

# 8.4 Busy vs Idle Connections

Suppose:

```text
max = 10
current = 6
```

and:

```text
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Idle
C5 → Idle
C6 → Idle
```

Then:

```text
Current connections = 6
Busy connections    = 3
Idle connections    = 3
Maximum             = 10
```

Visually:

```text
              Pool max = 10
                    │
       ┌────────────┴────────────┐
       │                         │
 Current = 6                 Capacity = 4
       │
   ┌───┴────┐
   ↓        ↓
 Busy     Idle
  3         3
```

This distinction becomes important when diagnosing pool performance.

---

# 8.5 Why Have a Maximum?

Without a maximum, your application could potentially create an uncontrolled number of database connections under heavy demand.

Imagine:

```text
10,000 requests
      ↓
10,000 database connections
```

That could overwhelm PostgreSQL.

Instead:

```text
10,000 requests
      ↓
Connection Pool
      ↓
max = 20
      ↓
Controlled DB connections
```

Additional operations can wait for available connections rather than forcing unlimited connection creation.

Therefore:

> **`max` provides a boundary around database connection usage for that pool.**

---

# 8.6 `max` Does Not Mean Maximum HTTP Requests

This is probably the most common misunderstanding.

Suppose:

```js
max: 10
```

You can still have:

```text
100 HTTP requests
```

or:

```text
1,000 HTTP requests
```

arriving at your server.

The architecture might look like:

```text
             1,000 HTTP Requests
                     │
                     ▼
               Node.js App
                     │
                     ▼
              PostgreSQL Pool
                     │
                 max = 10
                     │
          ┌──────────┼──────────┐
          ↓          ↓          ↓
         C1         C2         ...
                            C10
```

The pool limits **database connections**, not HTTP requests.

---

# 8.7 Then What Happens to the Other Requests?

Suppose:

```text
max = 3
```

and:

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

Now five more database operations need connections:

```text
Request D → Waiting
Request E → Waiting
Request F → Waiting
Request G → Waiting
Request H → Waiting
```

The pool doesn't create:

```text
C4
C5
C6
C7
C8
```

because it has reached:

```text
max = 3
```

Instead, operations wait for connections to become available, subject to timeout behaviour.

When:

```text
C1 → Finished
```

it can become available for another waiting operation.

---

# 8.8 Small Pool

Suppose:

```text
max = 2
```

Your application receives:

```text
100 concurrent DB operations
```

Conceptually:

```text
C1 → Busy
C2 → Busy

98 operations → Waiting
```

This could result in substantial waiting if database operations take significant time.

A pool that is too small can therefore become a bottleneck.

But don't jump to:

> "Then I'll set max to 1000."

That's the other extreme.

---

# 8.9 Large Pool

Suppose:

```text
max = 500
```

Your application might now be capable of creating hundreds of PostgreSQL connections.

That sounds powerful.

But PostgreSQL also has finite resources.

```text
Node.js
   │
   ├── C1
   ├── C2
   ├── ...
   └── C500
          │
          ▼
      PostgreSQL
```

A huge number of connections can consume significant database resources.

It can also create contention rather than improving throughput.

Therefore:

> **More connections does not automatically mean more performance.**

---

# 8.10 Database Work Is the Real Consideration

Suppose your application has:

```text
max = 20
```

and each query takes:

```text
5 ms
```

The pool may behave very differently compared with:

```text
max = 20
```

where each query takes:

```text
5 seconds
```

In the second situation, connections remain occupied much longer.

Therefore, pool sizing depends heavily on:

```text
Query duration
+
Concurrency
+
Database capacity
+
Application instances
+
Workload
```

---

# 8.11 Pool Size and Query Duration

Consider:

```text
max = 5
```

### Fast queries

```text
Request → Query → 5ms → Release
```

Connections become available quickly.

```text
C1 → Request A → Release
C1 → Request B → Release
C1 → Request C → Release
```

One connection can serve many operations over time.

### Slow queries

```text
Request → Query → 5 seconds → Release
```

Now:

```text
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

Other operations may wait.

So:

> **Pool pressure is affected by how long connections remain occupied.**

---

# 8.12 Pool Size and Concurrency

A useful simplified mental model is:

```text
Concurrency
     ↓
How many database operations
need connections at the same time
```

If many operations need database connections simultaneously:

```text
High concurrency
      ↓
More connection demand
      ↓
Pool may become saturated
```

But remember:

```text
HTTP concurrency
      ≠
Database concurrency
```

A request might spend time:

```text
HTTP Request
    ↓
Business logic
    ↓
Cache
    ↓
Database
    ↓
External API
```

Only part of its lifetime may require a database connection.

---

# 8.13 Connection Occupancy

A useful way to think about pool sizing is:

> **How long does each operation occupy a database connection?**

For example:

```text
Pool max = 10

Connection 1 → Query → 20ms
Connection 2 → Query → 20ms
...
```

Connections are released quickly.

But:

```text
Pool max = 10

Connection 1 → Transaction → 5s
Connection 2 → Transaction → 5s
...
```

Now the same pool can become saturated much more easily.

This is why **long transactions** are particularly important.

We'll return to this later.

---

# 8.14 Pool Size Is Per Pool

Suppose your Node.js application creates:

```text
Pool A → max 10
```

and accidentally creates another:

```text
Pool B → max 10
```

You don't have:

```text
Total max = 10
```

You potentially have:

```text
Pool A → 10
Pool B → 10

Potential total = 20
```

This is one reason you generally want a well-defined pool architecture rather than randomly creating pools throughout your application.

---

# 8.15 Pool Size Is Also Per Application Instance

This is **very important in production**.

Imagine your application runs three Node.js instances:

```text
                    PostgreSQL
                         ▲
              ┌──────────┼──────────┐
              │          │          │
           Server A   Server B   Server C
             Pool       Pool       Pool
             max=10     max=10     max=10
```

The database doesn't see:

```text
max = 10
```

as the total application-wide maximum.

Each application instance has its own pool.

Potentially:

```text
10 + 10 + 10 = 30 connections
```

So:

> **Pool size must be considered together with the number of application instances.**

---

# 8.16 A Simple Production Calculation

Suppose:

```text
Application instances = 4
Pool max per instance = 10
```

Potential maximum:

```text
4 × 10 = 40
```

database connections from those pools.

If you deploy:

```text
10 instances
```

with:

```text
max = 20
```

then the potential connection count becomes:

```text
10 × 20 = 200
```

That's why blindly choosing:

```text
max = 100
```

can become dangerous in horizontally scaled systems.

---

# 8.17 PostgreSQL Also Has `max_connections`

PostgreSQL itself has a connection limit:

```text
max_connections
```

For example, conceptually:

```text
PostgreSQL
max_connections = 100
```

Your application pools must operate within the database's overall connection capacity, while leaving room for:

* other application instances
* background workers
* administrative connections
* monitoring
* migrations
* maintenance
* reserved/superuser connections where applicable

Therefore:

```text
Application Pool
       ↓
PostgreSQL max_connections
```

are related but **not the same configuration**.

We'll dedicate the next section to this relationship.

---

# 8.18 Why Not Set Pool `max` Equal to PostgreSQL `max_connections`?

Suppose:

```text
PostgreSQL:
max_connections = 100
```

and you configure:

```text
Node.js pool:
max = 100
```

That might already be problematic.

Why?

Because PostgreSQL may need to accept connections from other sources.

```text
PostgreSQL
   │
   ├── Backend
   ├── Worker
   ├── Admin
   ├── Monitoring
   └── Other services
```

If one application pool consumes the entire connection capacity, everything else can suffer.

And if you have multiple application instances:

```text
Instance A → 100
Instance B → 100
Instance C → 100
```

you could massively exceed the database's capacity.

---

# 8.19 The Right Question

Don't ask:

> "What's the biggest `max` I can use?"

Ask:

> **"How many concurrent database connections does my workload actually need, and how many connections can my PostgreSQL infrastructure safely support?"**

That is the production-engineering question.

---

# 8.20 Pool Size Is a Capacity Decision

Think of it like this:

```text
             Database Capacity
                    │
                    ▼
          ┌────────────────────┐
          │ Available DB       │
          │ connection budget  │
          └──────────┬─────────┘
                     │
             Distribute across
              application pools
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
      Pool A       Pool B       Pool C
```

Pool configuration should fit inside that broader capacity budget.

---

# 8.21 Don't Increase the Pool to Hide Slow Queries

This is a common production mistake.

Suppose:

```text
Pool max = 10
```

and you're seeing waiting operations.

Someone might say:

> "Increase it to 50."

But what if the real problem is:

```text
Slow SQL query
       ↓
Connection remains busy
       ↓
Pool fills
       ↓
Requests wait
```

Increasing the pool may simply create more simultaneous expensive queries.

The actual fix might be:

```text
Slow query
   ↓
Analyse query
   ↓
Index / query optimisation
   ↓
Shorter execution time
   ↓
Connections released faster
```

Therefore:

> **Pool saturation can be a symptom, not necessarily the root cause.**

---

# 8.22 Another Important Example: Long Transactions

Suppose:

```text
max = 10
```

and ten requests each start a transaction:

```text
C1 → Transaction
C2 → Transaction
C3 → Transaction
...
C10 → Transaction
```

All connections are now occupied.

Even if the SQL statements themselves aren't constantly running, the connections remain checked out while the transactions are open.

Then:

```text
Request 11
    ↓
Pool
    ↓
No connection
    ↓
Wait
```

This is why transactions should generally be kept **short and focused**.

We'll cover this in depth later.

---

# 8.23 A Useful Mental Model

Think of:

```text
max
```

as the number of **database communication channels your application is willing to have concurrently available through that pool**.

It is not:

```text
Users
```

It is not:

```text
HTTP requests
```

It is not:

```text
Queries per second
```

It is not:

```text
CPU cores
```

It's specifically about:

> **database connections managed by that pool.**

---

# 8.24 Example Architecture

Suppose:

```text
3 Node.js instances
```

Each has:

```text
max = 10
```

Architecture:

```text
                    PostgreSQL
                         ▲
                         │
             ┌───────────┼───────────┐
             │           │           │
             │           │           │
         Instance A  Instance B  Instance C
         Pool max10  Pool max10  Pool max10
             │           │           │
           C1-C10      C1-C10      C1-C10
```

Potential maximum from those pools:

```text
3 × 10 = 30
```

Then if you add:

```text
2 worker processes
```

with:

```text
max = 5
```

you could potentially have:

```text
30 + 5 + 5 = 40
```

connections.

That's the kind of calculation you need to think about in production.

---

# 8.25 What Should You Actually Configure?

There is **no universal magic number**.

You should consider:

```text
1. PostgreSQL capacity
2. Number of application instances
3. Expected concurrency
4. Query execution time
5. Transaction duration
6. Other database clients
7. Available CPU/memory
8. Workload characteristics
9. Observed pool wait time
10. Observed database performance
```

Then benchmark and monitor.

Start conservatively rather than blindly configuring a huge pool.

---

# Key Takeaways

### `max`

```js
new Pool({
  max: 10
});
```

means the pool has a maximum connection capacity of 10 according to `node-postgres`'s pool semantics.

It does **not** mean:

```text
10 users
10 requests
10 queries/second
10 connections necessarily created immediately
```

### Pool size hierarchy

```text
                    PostgreSQL
                         │
                  max_connections
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
         Instance A   Instance B   Instance C
          Pool max10   Pool max10   Pool max10
```

Potential application connection count:

```text
instances × pool max
```

plus connections from other services/processes.

### Most important principle

> **Pool size is a capacity-management decision, not a number you maximise for the sake of performance.**

And:

> **If a pool is saturated, investigate why connections are staying busy before simply increasing the pool size.**

---

# 9. `min` and Minimum Pool Size

Next we'll cover **minimum pool size**, how it differs from `max`, whether you actually need it with `node-postgres`, when maintaining idle connections makes sense, and an important detail: **don't blindly assume that every PostgreSQL pool library exposes or implements `min` the same way.**

# 9. Minimum Pool Size — `min`

Now we need to clear up an important point before going further:

> **`min` is not a universal PostgreSQL setting.**

It is a **connection-pool configuration concept**, and different pooling libraries implement it differently.

Since you're learning PostgreSQL with Node.js, we're primarily interested in how this relates to **`node-postgres` (`pg`)**.

---

# 9.1 What Is Minimum Pool Size?

A minimum pool size generally describes a desired lower bound on how many connections a pool keeps available, depending on the pooling implementation.

Conceptually:

```text
min = 3
max = 10
```

means the pool is configured with:

```text
Minimum target → 3 connections
Maximum        → 10 connections
```

So conceptually:

```text
                 Pool
        ┌─────────────────────┐
        │ C1                  │
        │ C2                  │ ← minimum baseline
        │ C3                  │
        │                     │
        │ C4 ... C10         │ ← can grow with demand
        └─────────────────────┘
```

The exact semantics depend on the pool implementation.

---

# 9.2 `min` vs `max`

This is the easiest way to understand them:

```text
min → lower/baseline connection target
max → upper connection limit
```

For example:

```text
min = 2
max = 10
```

Think:

```text
0 ─── 2 ─────────────── 10
     ↑                  ↑
    min                max
```

Where:

* `min` describes the desired baseline.
* `max` describes the maximum capacity.

---

# 9.3 Why Would We Keep Connections Open When They're Idle?

You might ask:

> "If nobody is using the database, why keep connections around?"

Because establishing a new connection has overhead.

Imagine:

```text
No connections
      ↓
Request arrives
      ↓
Create connection
      ↓
Authenticate
      ↓
Execute query
```

If the application already has an idle connection:

```text
Idle connection
      ↓
Request arrives
      ↓
Reuse connection
      ↓
Execute query
```

The second path can avoid connection-establishment work.

---

# 9.4 The Trade-off

Keeping idle connections has a cost.

```text
More idle connections
        ↓
More resources consumed
```

But:

```text
Fewer idle connections
        ↓
Potentially more connection creation
        ↓
More connection-establishment overhead
```

So there is a trade-off:

```text
Performance
    ↕
Resource usage
```

This is why you shouldn't simply make `min` huge.

---

# 9.5 Important `pg` Detail

For `node-postgres`, the most important pool-size setting you will commonly work with is:

```js
max
```

For example:

```js
const pool = new Pool({
  max: 10
});
```

`node-postgres` does **not** use a traditional `min` configuration in the same way some other connection-pool implementations do.

This matters because you'll encounter examples from other ecosystems such as:

```text
min
max
idleTimeoutMillis
```

and might assume:

> "Every PostgreSQL pool must have `min`."

No.

**Pooling is a client-side mechanism, not a PostgreSQL SQL/database setting, and pool APIs differ by library.**

So for your `pg` notes:

```text
PostgreSQL itself
    ↓
Doesn't have "minimum pool size"

node-postgres
    ↓
Uses its own pool behaviour/configuration
```

---

# 9.6 Don't Confuse `min` With PostgreSQL `min_connections`

There isn't a PostgreSQL server setting that means:

```text
min_connections
```

analogous to:

```text
max_connections
```

PostgreSQL has:

```text
max_connections
```

which controls server-side connection capacity.

A minimum pool size, where supported, is a **client-side pool concept**.

So:

```text
PostgreSQL
└── max_connections

Connection Pool
├── min  ← if supported by that pool
└── max
```

These belong to different layers.

---

# 9.7 Why This Distinction Matters

Consider:

```text
PostgreSQL
max_connections = 100
```

and:

```text
Application Pool
max = 10
```

The pool might use up to ten connections, while PostgreSQL allows up to its configured server-side connection capacity.

The relationship is:

```text
Application
     ↓
Pool
     ↓
PostgreSQL
```

not:

```text
Application
     ↓
PostgreSQL max_connections directly
```

The pool is one of the clients consuming PostgreSQL's connection capacity.

---

# 9.8 Minimum Connections and Application Startup

In a pool implementation that actively maintains a minimum number of connections, startup could conceptually look like:

```text
Application starts
       ↓
Pool starts
       ↓
Establish baseline connections
       ↓
C1
C2
C3
       ↓
Ready
```

Then traffic increases:

```text
C1 → Busy
C2 → Busy
C3 → Busy
       ↓
Demand increases
       ↓
C4
C5
C6
       ↓
...
```

Eventually:

```text
max
```

is reached.

Again, this is the **general pool concept**; don't assume this exact startup behaviour for `pg`.

---

# 9.9 Minimum Pool Size and Idle Connections

Suppose a library supports:

```text
min = 3
max = 10
```

After traffic disappears:

```text
C1 → Idle
C2 → Idle
C3 → Idle
C4 → Idle
C5 → Idle
```

The pool may eventually reduce its idle connections according to its policies, potentially maintaining the configured baseline.

Conceptually:

```text
5 idle
   ↓
Idle management
   ↓
3 connections remain
```

The exact behaviour depends on the implementation.

This is why you should always check the documentation for the **specific pool library** you're using.

---

# 9.10 `min` Isn't "Three Connections Always Doing Work"

This is another common misunderstanding.

If:

```text
min = 3
```

it does not mean:

```text
3 queries are always running
```

It refers to connections, not database work.

You could have:

```text
C1 → Idle
C2 → Idle
C3 → Idle
```

and:

```text
0 active queries
```

while still maintaining three connections.

So:

```text
Connections ≠ Queries
```

---

# 9.11 `min` Isn't a Concurrency Limit

Suppose:

```text
min = 3
max = 10
```

`min = 3` does not mean:

```text
Only 3 requests can access PostgreSQL.
```

If demand increases, the pool can potentially grow toward:

```text
max = 10
```

depending on its implementation.

Therefore:

```text
min
 ↓
baseline

max
 ↓
capacity
```

---

# 9.12 When a Minimum Can Be Useful

A minimum connection count can make sense when:

### 1. Your application receives regular traffic

If the application continuously needs the database:

```text
Traffic
████████████████████
```

keeping some connections available can reduce repeated connection establishment.

### 2. Connection establishment is relatively expensive

For example, when the database is remote:

```text
Application
      │
      │ Network
      ▼
Cloud PostgreSQL
```

There can be more connection-establishment latency than with a local database.

### 3. You want predictable warm capacity

A warm pool can reduce the amount of time needed to establish initial connections when traffic arrives.

But these decisions should be based on actual workload and measurements.

---

# 9.13 When You Don't Need a Large Minimum

Suppose your application receives occasional traffic:

```text
Request
    ↓
   ...
5 minutes
    ↓
Request
```

Maintaining a large number of idle connections may not be useful.

You might instead prefer:

```text
Few idle connections
        ↓
Lower resource consumption
```

rather than:

```text
Many idle connections
        ↓
Resources continuously reserved
```

Again, the right answer depends on the infrastructure and pool implementation.

---

# 9.14 `min` and Database Capacity

Imagine a system with:

```text
PostgreSQL max_connections = 100
```

and:

```text
10 application instances
```

If every instance maintains:

```text
min = 10
```

you could already have:

```text
10 × 10 = 100
```

connections just from the minimum pool baseline.

That leaves little or no room for:

* traffic-driven additional connections
* background workers
* administration
* migrations
* monitoring
* other services

This demonstrates why minimum connection settings must be considered at the **whole-system level**.

---

# 9.15 The Connection Budget

A useful production concept is a **connection budget**.

Suppose:

```text
PostgreSQL connection capacity = 100
```

You might conceptually allocate:

```text
API instances       → 60
Background workers  → 20
Admin/maintenance   → 10
Reserved headroom   → 10
```

Then:

```text
60 + 20 + 10 + 10 = 100
```

This isn't a universal formula; it's a mental model for capacity planning.

The key idea:

> **Don't treat PostgreSQL's entire connection capacity as belonging to one application pool.**

---

# 9.16 Minimum vs Maximum — Visual Summary

```text
Connections
    │
  10│                         ← max
    │                    ┌──────────┐
    │                    │          │
    │          ┌─────────┤          │
    │          │         │          │
    │          │         │          │
   3│──────────┤         │          │
    │          │         │          │
    │          │         │          │
   0└──────────┴─────────┴──────────┴──→ Time
              min
```

Conceptually:

```text
min
 ↓
Keep a baseline/warm capacity

max
 ↓
Never exceed this pool capacity
```

---

# 9.17 What You Should Remember for `pg`

Since your stack is Node.js + PostgreSQL, put this prominently in your notes:

> **Do not assume that every connection pool has the same configuration API.**

For `node-postgres`:

```js
const pool = new Pool({
  max: 10
});
```

The commonly important pool-size control is:

```text
max
```

You'll also encounter other options for idle management and connection establishment, such as:

```text
idleTimeoutMillis
connectionTimeoutMillis
```

These are separate concepts and we'll cover them later.

---

# 9.18 Terminology Summary

| Term                             | Meaning                                                                          |
| -------------------------------- | -------------------------------------------------------------------------------- |
| **`min`**                        | Minimum/baseline pool connection concept in pool implementations that support it |
| **`max`**                        | Maximum pool connection capacity                                                 |
| **Idle connection**              | Existing connection not currently checked out                                    |
| **Warm connection**              | Existing ready-to-use connection                                                 |
| **Current connections**          | Connections currently maintained by the pool                                     |
| **PostgreSQL `max_connections`** | Server-side maximum connection capacity                                          |
| **Connection budget**            | Planned allocation of DB connections across services/instances                   |

---

# Key Takeaways

### Don't confuse the layers

```text
                 PostgreSQL
              max_connections
                     │
                     ▼
             Connection capacity
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
        Pool A      Pool B     Pool C
```

### Pool concepts

```text
min
 ↓
Baseline / minimum target
(if supported by the pool)

max
 ↓
Maximum pool capacity
```

### For `node-postgres`

The important practical configuration is:

```js
const pool = new Pool({
  max: 10
});
```

Don't blindly copy a `min` option from another PostgreSQL client/pooling library and assume it has the same meaning in `pg`.

### Most important lesson

> **`min` and `max` belong to the connection-pool layer, while PostgreSQL's `max_connections` belongs to the database-server layer. They solve different problems and must be considered together when designing a production system.**

---

# 10. `pool.query()` vs `pool.connect()`

Next we'll get hands-on with the **two most important ways you'll interact with `pg.Pool`**:

```js
pool.query()
```

vs.

```js
pool.connect()
```

We'll understand exactly what happens with acquisition and release, when `pool.query()` is the right choice, when you need `pool.connect()`, and why **transactions require the latter**.

# 10. `pool.query()` vs `pool.connect()`

This is one of the most practical parts of PostgreSQL connection pooling with Node.js.

Once you understand this distinction, you'll know **when the pool should manage the connection for you and when you need direct control over a connection**.

With `node-postgres` (`pg`), you'll commonly encounter:

```js
pool.query()
```

and:

```js
pool.connect()
```

They both use the connection pool, but they serve different purposes.

---

# 10.1 `pool.query()`

For a normal, standalone SQL query, you can simply do:

```js
const result = await pool.query(
  "SELECT * FROM users"
);
```

You don't manually acquire or release a connection.

Conceptually, `pool.query()` does something like:

```text
pool.query()
     ↓
Find/acquire a connection
     ↓
Execute query
     ↓
Release connection
     ↓
Return result
```

The pool handles the connection lifecycle for you.

---

# 10.2 Example

Suppose you have:

```js
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
});
```

Then:

```js
const result = await pool.query(
  "SELECT * FROM users WHERE id = $1",
  [userId]
);

console.log(result.rows);
```

You don't need:

```js
const client = await pool.connect();
```

and you don't need:

```js
client.release();
```

because `pool.query()` handles the necessary acquisition and release for a standalone query.

---

# 10.3 Why `pool.query()` Is Convenient

Imagine you have:

```text
GET /users
```

and your database work is simply:

```sql
SELECT * FROM users;
```

You don't need to manually manage a connection.

Your flow becomes:

```text
HTTP Request
     ↓
Route Handler
     ↓
pool.query()
     ↓
PostgreSQL
     ↓
Result
     ↓
HTTP Response
```

This is usually exactly what you want for an independent query.

---

# 10.4 `pool.connect()`

Now consider:

```js
const client = await pool.connect();
```

This explicitly acquires a client/connection from the pool.

Conceptually:

```text
Application
     ↓
pool.connect()
     ↓
Connection Pool
     ↓
Connection
```

Now your code has direct control over that connection.

You can execute:

```js
await client.query(...);
```

multiple times.

When you're finished:

```js
client.release();
```

returns it to the pool.

---

# 10.5 Basic `pool.connect()` Pattern

The standard safe pattern is:

```js
const client = await pool.connect();

try {
  const result = await client.query(
    "SELECT * FROM users"
  );

  return result.rows;
} finally {
  client.release();
}
```

The lifecycle is:

```text
pool.connect()
      ↓
Acquire
      ↓
Use
      ↓
try
      ↓
finally
      ↓
client.release()
      ↓
Pool
```

The `finally` block ensures that the connection is returned even if an error occurs.

---

# 10.6 Why Would We Need Direct Control?

You need direct connection control when **multiple operations must happen on the same PostgreSQL connection**.

The most important example is:

# Transactions

Suppose you need:

```sql
BEGIN;

INSERT INTO orders (...);

UPDATE inventory
SET quantity = quantity - 1
WHERE id = 123;

COMMIT;
```

These operations belong to the same transaction.

You therefore need to keep using the **same connection** throughout the transaction.

---

# 10.7 Transactions Need One Connection

Consider:

```text
Pool
 ├── C1
 ├── C2
 └── C3
```

You start a transaction on C1:

```text
C1
 │
 ├── BEGIN
 ├── INSERT
 ├── UPDATE
 └── COMMIT
```

All those commands need to happen within the same session/connection.

You don't want:

```text
BEGIN  → C1
INSERT → C2
UPDATE → C3
COMMIT → C1
```

That is not one coherent transaction.

This is why you use:

```js
const client = await pool.connect();
```

and keep that client for the entire transaction.

---

# 10.8 Transaction Example

A standard pattern looks like:

```js
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query(
    "INSERT INTO orders (...) VALUES (...)"
  );

  await client.query(
    "UPDATE inventory SET quantity = quantity - 1 WHERE id = $1",
    [productId]
  );

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

The lifecycle is:

```text
Acquire C1
    ↓
BEGIN
    ↓
Query 1
    ↓
Query 2
    ↓
COMMIT / ROLLBACK
    ↓
Release C1
```

We'll cover transactions in much more detail later.

---

# 10.9 Why Not Use `pool.query()` for a Transaction?

You might be tempted to write:

```js
await pool.query("BEGIN");

await pool.query("INSERT ...");

await pool.query("UPDATE ...");

await pool.query("COMMIT");
```

This is dangerous because each call to `pool.query()` is an independent interaction with the pool.

The pool can potentially assign different connections to different calls:

```text
pool.query("BEGIN")
       ↓
      C1

pool.query("INSERT")
       ↓
      C2

pool.query("UPDATE")
       ↓
      C3

pool.query("COMMIT")
       ↓
      C1
```

Now your statements aren't necessarily part of the same transaction.

Therefore:

> **For transactions, acquire one client and keep all transaction statements on that client.**

---

# 10.10 `pool.query()` Is Ideal for Independent Queries

Examples:

```js
await pool.query(
  "SELECT * FROM users WHERE id = $1",
  [id]
);
```

```js
await pool.query(
  "INSERT INTO users (name) VALUES ($1)",
  [name]
);
```

```js
await pool.query(
  "UPDATE users SET name = $1 WHERE id = $2",
  [name, id]
);
```

Each operation is independent.

So:

```text
Query
 ↓
pool.query()
```

is usually the simplest approach.

---

# 10.11 `pool.connect()` Is More Powerful

With:

```js
const client = await pool.connect();
```

you can do:

```text
Acquire
   ↓
Query
   ↓
Query
   ↓
Query
   ↓
Release
```

This gives you control over **which connection/session** is used throughout that sequence.

This matters for:

* transactions
* session-level state
* multiple queries that must use the same connection
* explicit connection lifecycle management

---

# 10.12 `pool.query()` vs `pool.connect()`

Here's the important comparison:

| `pool.query()`                   | `pool.connect()`               |
| -------------------------------- | ------------------------------ |
| Convenient                       | More control                   |
| Good for standalone queries      | Good for multi-step operations |
| Pool manages acquisition/release | You manage the acquired client |
| No manual `release()`            | Must call `client.release()`   |
| Simple CRUD queries              | Transactions                   |
| Less code                        | More responsibility            |

---

# 10.13 Mental Model

Think:

```text
pool.query()
```

as:

> "Pool, please execute this independent query for me."

Whereas:

```text
pool.connect()
```

means:

> "Pool, give me a connection. I'll manage this connection for a while."

---

# 10.14 `pool.query()` Internally

Conceptually:

```text
                  pool.query()
                       │
                       ▼
                Connection Pool
                       │
              ┌────────┴────────┐
              │                 │
         Idle available?       No?
              │                 │
              ▼                 ▼
          Acquire          Create/wait
              │
              ▼
         Execute query
              │
              ▼
           Release
              │
              ▼
          Return result
```

The implementation details are handled by `pg`.

---

# 10.15 `pool.connect()` Internally

Conceptually:

```text
                 pool.connect()
                       │
                       ▼
                Connection Pool
                       │
                       ▼
                  Acquire C1
                       │
                       ▼
                 Your code
                       │
              ┌────────┴────────┐
              │                 │
           Query 1           Query 2
              │                 │
              └────────┬────────┘
                       │
                       ▼
                client.release()
                       │
                       ▼
                     Pool
```

You now own the responsibility of returning the client.

---

# 10.16 A Very Important Rule

Whenever you write:

```js
const client = await pool.connect();
```

immediately think:

```text
"I am responsible for releasing this."
```

The safest pattern is:

```js
const client = await pool.connect();

try {
  // database operations
} finally {
  client.release();
}
```

Don't rely on remembering to release it later.

---

# 10.17 What Happens If You Don't Release?

Suppose:

```js
const client = await pool.connect();

await client.query("SELECT ...");

// No release!
```

The pool considers the client checked out.

It may remain unavailable to other operations.

Repeated enough times:

```text
C1 → Checked out
C2 → Checked out
C3 → Checked out
C4 → Checked out
C5 → Checked out
```

Eventually:

```text
Pool
 ↓
No available connections
 ↓
Requests wait/fail
```

This is called a **connection leak**.

We'll have an entire section dedicated to it.

---

# 10.18 Don't Call `client.release()` Too Early

The opposite mistake is also possible.

For example:

```js
const client = await pool.connect();

await client.query("BEGIN");

client.release(); // ❌

await client.query("UPDATE ...");
```

You've returned the connection to the pool while your transaction/work still needs it.

That's unsafe.

The correct lifecycle is:

```text
Acquire
 ↓
Complete all required work
 ↓
COMMIT / ROLLBACK
 ↓
Release
```

---

# 10.19 Standalone Queries

For ordinary CRUD:

```text
SELECT
INSERT
UPDATE
DELETE
```

if each operation is independent:

```js
await pool.query(...);
```

is generally the cleanest approach.

For example:

```js
const { rows } = await pool.query(
  "SELECT id, name FROM users WHERE id = $1",
  [id]
);
```

---

# 10.20 Multiple Queries Don't Automatically Mean `pool.connect()`

This is a subtle point.

You don't necessarily need `pool.connect()` simply because you have two queries.

For example:

```js
await pool.query("SELECT ...");
await pool.query("SELECT ...");
```

may be perfectly fine if the queries are independent.

The important question is:

> **Do these operations need to share the same connection/session or transaction?**

If no:

```text
pool.query()
```

If yes:

```text
pool.connect()
```

That's a much better rule than:

> "One query = `pool.query`, multiple queries = `pool.connect`."

---

# 10.21 Example: Independent Queries

Suppose an API needs:

```text
User data
+
Product data
```

and there is no transaction or session dependency.

You can simply do:

```js
const userResult = await pool.query(
  "SELECT * FROM users WHERE id = $1",
  [userId]
);

const productResult = await pool.query(
  "SELECT * FROM products WHERE id = $1",
  [productId]
);
```

No manually acquired client is required.

---

# 10.22 Example: Dependent Transaction

Now suppose you're transferring money:

```text
Account A
   ↓
Subtract $100

Account B
   ↓
Add $100
```

These operations must succeed or fail together.

You need a transaction:

```text
Acquire C1
   ↓
BEGIN
   ↓
UPDATE Account A
   ↓
UPDATE Account B
   ↓
COMMIT
   ↓
Release C1
```

This requires:

```js
const client = await pool.connect();
```

---

# 10.23 Another Reason for `pool.connect()`: Session State

A PostgreSQL connection/session can have state associated with it.

For example, some operations/settings are connection- or session-specific.

If you need several operations to occur within the same session, you need to keep the same client.

Conceptually:

```text
C1
 │
 ├── Set session state
 ├── Query 1
 ├── Query 2
 └── Query 3
```

If you instead use separate `pool.query()` calls:

```text
Query 1 → C1
Query 2 → C2
Query 3 → C3
```

you cannot assume the same session is being used.

So:

> **Use an explicitly acquired client whenever connection/session affinity matters.**

---

# 10.24 The Decision Tree

Put this in your README:

```text
Need to execute SQL?
       │
       ▼
Is the operation independent?
       │
   ┌───┴───┐
  Yes      No
   │        │
   ▼        ▼
pool.query()   Do multiple operations
               need the SAME connection?
                      │
                      ▼
                 pool.connect()
                      │
                      ▼
                 Use client
                      │
                      ▼
                release client
```

Or the simpler version:

```text
Standalone query
      ↓
pool.query()

Transaction / same-session work
      ↓
pool.connect()
      ↓
client.query(...)
      ↓
client.release()
```

---

# 10.25 Complete Comparison Example

### Simple query

```js
const result = await pool.query(
  "SELECT * FROM users WHERE id = $1",
  [userId]
);
```

Lifecycle:

```text
Pool
 ↓
Acquire
 ↓
Query
 ↓
Release
 ↓
Result
```

### Explicit connection

```js
const client = await pool.connect();

try {
  const result = await client.query(
    "SELECT * FROM users WHERE id = $1",
    [userId]
  );

  return result.rows;
} finally {
  client.release();
}
```

Lifecycle:

```text
Pool
 ↓
Acquire
 ↓
Your code
 ↓
Query
 ↓
Release
 ↓
Pool
```

### Transaction

```js
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query("UPDATE ...");
  await client.query("INSERT ...");

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Lifecycle:

```text
Pool
 ↓
Acquire C1
 ↓
BEGIN
 ↓
Query 1
 ↓
Query 2
 ↓
COMMIT / ROLLBACK
 ↓
Release C1
 ↓
Pool
```

---

# 10.26 The Golden Rule

Memorise this:

> **Use `pool.query()` for independent queries. Use `pool.connect()` when you need explicit control over a connection, especially when multiple operations must run on the same connection, such as a transaction.**

And:

> **If you acquire a client with `pool.connect()`, make sure you release it with `client.release()`—preferably in a `finally` block.**

---

# Key Takeaways

### `pool.query()`

```js
await pool.query("SELECT ...");
```

Best for:

```text
Independent SQL operation
       ↓
Pool manages connection
       ↓
Query
       ↓
Connection returned
```

### `pool.connect()`

```js
const client = await pool.connect();
```

Best when:

```text
You need a specific connection
       ↓
Multiple operations
       ↓
Same connection/session
```

Then:

```js
client.release();
```

### Transactions

Always think:

```text
pool.connect()
     ↓
BEGIN
     ↓
Query
     ↓
Query
     ↓
COMMIT / ROLLBACK
     ↓
client.release()
```

### One final distinction

Don't use this rule:

```text
1 query   → pool.query()
2 queries → pool.connect()
```

Instead use:

```text
Independent work
    → pool.query()

Same connection/session required
    → pool.connect()
```

That's the correct mental model.

---

# 11. Transactions and Connection Pooling

This is the **big one**.

Next we'll go deep into why a PostgreSQL transaction must stay on **one connection**, how `BEGIN → queries → COMMIT/ROLLBACK` interacts with the pool, what happens if you accidentally use `pool.query()` inside a transaction, and why a transaction that holds a connection for too long can starve your pool.

# 11. Transactions and Connection Pooling

This is one of the **most important connections between PostgreSQL and connection pooling**.

If you understand this section properly, you'll understand why `pool.connect()` exists, why `client.release()` matters, and why a badly managed transaction can exhaust an otherwise healthy connection pool.

---

# 11.1 First: What Is a Transaction?

A PostgreSQL transaction groups multiple database operations into a single logical unit of work.

The basic idea is:

```text
Start transaction
      ↓
Operation 1
      ↓
Operation 2
      ↓
Operation 3
      ↓
Commit
```

If something goes wrong:

```text
Start transaction
      ↓
Operation 1
      ↓
Operation 2
      ↓
ERROR
      ↓
Rollback
```

The transaction allows PostgreSQL to treat the group of operations according to the transaction's atomicity and consistency requirements.

---

# 11.2 Basic Transaction Commands

The fundamental SQL commands are:

```sql id="e9x5f1"
BEGIN;
```

Then:

```sql id="v6wy5h"
-- SQL operations
```

And finally:

```sql id="2jbx2g"
COMMIT;
```

or:

```sql id="2d1z8p"
ROLLBACK;
```

So:

```text id="1cx8qp"
BEGIN
  ↓
Queries
  ↓
COMMIT
```

or:

```text id="7t3t6p"
BEGIN
  ↓
Queries
  ↓
ROLLBACK
```

---

# 11.3 Why Does Connection Pooling Matter?

Here's the critical concept:

> **A PostgreSQL transaction is associated with a database session/connection.**

Therefore, the statements belonging to a transaction must be executed on the **same PostgreSQL connection**.

For example:

```text id="2l1w8s"
Connection C1
    │
    ├── BEGIN
    ├── INSERT
    ├── UPDATE
    └── COMMIT
```

That's one transaction.

---

# 11.4 Why Can't We Randomly Switch Connections?

Suppose your pool contains:

```text id="a0d9kw"
C1
C2
C3
```

You do:

```sql id="c9h3nd"
BEGIN;
```

on C1.

Now PostgreSQL considers C1 to be inside a transaction.

Then imagine:

```sql id="m2k4dx"
INSERT ...;
```

gets executed on C2.

That's a different session.

Then:

```sql id="w9e7a8"
COMMIT;
```

gets executed on C1.

You would effectively have:

```text id="3t4d0z"
C1 → BEGIN
C2 → INSERT
C1 → COMMIT
```

The `INSERT` was not part of C1's transaction.

That's why you need to keep the same connection throughout the transaction.

---

# 11.5 Correct Transaction Architecture

With a pool:

```text id="b6h8jy"
Connection Pool
      │
      │ acquire
      ▼
     C1
      │
      ├── BEGIN
      ├── Query 1
      ├── Query 2
      ├── Query 3
      └── COMMIT
      │
      │ release
      ▼
Connection Pool
```

The connection is checked out for the entire transaction.

---

# 11.6 Node.js Example

Using `pg`:

```js id="5a1c7d"
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query(
    "INSERT INTO orders (...) VALUES (...)"
  );

  await client.query(
    "UPDATE inventory SET quantity = quantity - 1 WHERE id = $1",
    [productId]
  );

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Notice the same:

```js id="i2s3s8"
client
```

is used for every query.

---

# 11.7 Transaction Lifecycle

The complete lifecycle is:

```text id="w9v6qf"
Pool
 ↓
Acquire connection
 ↓
BEGIN
 ↓
Query 1
 ↓
Query 2
 ↓
Query 3
 ↓
COMMIT
 ↓
Release connection
 ↓
Pool
```

If something fails:

```text id="9a1kqh"
Pool
 ↓
Acquire
 ↓
BEGIN
 ↓
Query 1
 ↓
Query 2
 ↓
ERROR
 ↓
ROLLBACK
 ↓
Release
 ↓
Pool
```

This pattern is fundamental.

---

# 11.8 Why `pool.query()` Is Dangerous for Multi-Step Transactions

You might write:

```js id="5p8e8m"
await pool.query("BEGIN");

await pool.query("INSERT ...");

await pool.query("UPDATE ...");

await pool.query("COMMIT");
```

This is **not the correct way to manage a transaction with a pool**.

Why?

Because each `pool.query()` is an independent interaction with the pool.

You cannot assume all calls use the same connection.

Conceptually:

```text id="bjr1k6"
pool.query("BEGIN")
       ↓
      C1

pool.query("INSERT")
       ↓
      C2

pool.query("UPDATE")
       ↓
      C3

pool.query("COMMIT")
       ↓
      C1
```

Now:

```text id="o0f1bw"
C1 → BEGIN
C2 → INSERT
C3 → UPDATE
C1 → COMMIT
```

That is not one transaction containing all three operations.

---

# 11.9 Correct Approach

Instead:

```js id="3evp3k"
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query("INSERT ...");

  await client.query("UPDATE ...");

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Now:

```text id="m6c0u6"
C1
 │
 ├── BEGIN
 ├── INSERT
 ├── UPDATE
 └── COMMIT
```

All operations use the same connection.

---

# 11.10 Why Transactions Hold Connections

Once you do:

```js id="y5qgpr"
const client = await pool.connect();
```

the connection is checked out.

Then:

```js id="fj9n0k"
await client.query("BEGIN");
```

starts a transaction on that connection.

You should keep that connection until:

```text id="x7r6vz"
COMMIT
```

or:

```text id="u8h0yl"
ROLLBACK
```

Only then:

```js id="9g8s47"
client.release();
```

---

# 11.11 Why Long Transactions Are Dangerous

This is where transactions directly affect pool capacity.

Suppose:

```text id="rj7x4s"
Pool max = 5
```

Five requests start transactions:

```text id="y6z2wv"
C1 → Transaction
C2 → Transaction
C3 → Transaction
C4 → Transaction
C5 → Transaction
```

Now:

```text id="4w1nzk"
Idle connections = 0
Busy connections = 5
```

A sixth request arrives:

```text id="0f0yyf"
Request 6
    ↓
Pool
    ↓
No available connection
    ↓
Waiting
```

If those transactions take a long time, Request 6 keeps waiting.

---

# 11.12 What Makes a Transaction "Long"?

Not just slow SQL.

This is a common mistake:

```js id="2z6njv"
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query("UPDATE ...");

  await callExternalAPI(); // ❌

  await client.query("INSERT ...");

  await client.query("COMMIT");
} finally {
  client.release();
}
```

The database connection is held while waiting for an external API.

Imagine:

```text id="c0tq7b"
BEGIN
 ↓
Database query
 ↓
External API
 ↓
5 seconds waiting
 ↓
Database query
 ↓
COMMIT
 ↓
Release
```

During those five seconds:

```text id="9vlp6s"
Connection = occupied
```

That connection cannot be used by another pool operation.

So:

> **Don't hold a database connection while performing unrelated slow work whenever you can avoid it.**

---

# 11.13 Transactions and Pool Starvation

Suppose:

```text id="8p7s8c"
Pool max = 10
```

and all ten connections are occupied by long-running transactions:

```text id="5w2g0f"
C1 → Transaction
C2 → Transaction
C3 → Transaction
...
C10 → Transaction
```

Now:

```text id="q3o5n1"
Pool available = 0
```

Other database operations must wait.

This can cause:

```text id="g9g8fk"
Long transactions
      ↓
Connections remain checked out
      ↓
Pool saturation
      ↓
Requests wait
      ↓
Application latency increases
```

That's **pool starvation**.

---

# 11.14 Transaction Failure Handling

Always think about both success and failure.

### Success

```text id="2egxhl"
BEGIN
 ↓
Query
 ↓
Query
 ↓
COMMIT
 ↓
Release
```

### Failure

```text id="7zbyl9"
BEGIN
 ↓
Query
 ↓
ERROR
 ↓
ROLLBACK
 ↓
Release
```

Don't simply do:

```js id="3tr4c7"
catch (error) {
  throw error;
}
```

without considering the transaction state.

A failed transaction needs to be properly handled before returning the connection to the pool.

---

# 11.15 Why Rollback Matters Before Release

Suppose:

```text id="cjqgqr"
C1
 ↓
BEGIN
 ↓
Query
 ↓
ERROR
```

If you simply release the connection without properly handling the transaction:

```text id="h9m8al"
C1
 ↓
release()
 ↓
Pool
```

you risk returning a connection whose session isn't in the clean state your next operation expects.

The safe transaction pattern is:

```text id="l5v7bl"
Error
 ↓
ROLLBACK
 ↓
Release
```

This is why the standard pattern has:

```js id="f4w0i1"
catch (error) {
  await client.query("ROLLBACK");
  throw error;
}
```

followed by:

```js id="n5n0a8"
finally {
  client.release();
}
```

---

# 11.16 Transactions and Connection State

This is another reason the same connection matters.

PostgreSQL maintains transaction state at the session/connection level.

Conceptually:

```text id="y2c3p7"
C1
 │
 ├── Transaction state
 ├── Session state
 └── SQL operations
```

If you switch connections:

```text id="f9t8q1"
C1 → BEGIN
C2 → Query
```

you're no longer operating inside the same session/transaction.

So:

> **Transaction state follows the connection.**

---

# 11.17 Example: Bank Transfer

Suppose we have:

```text id="q5n5n8"
Account A = ₹10,000
Account B = ₹5,000
```

We transfer:

```text id="r2k6vl"
₹1,000
```

We need:

```text id="0n8y1d"
Subtract ₹1,000 from A
+
Add ₹1,000 to B
```

If the first query succeeds but the second fails:

```text id="5x7h08"
A = ₹9,000
B = ₹5,000
```

That's incorrect.

A transaction lets us make both operations part of one unit:

```text id="f3my0a"
BEGIN
  ↓
A -= ₹1,000
  ↓
B += ₹1,000
  ↓
COMMIT
```

If something fails:

```text id="rxz8e7"
BEGIN
  ↓
A -= ₹1,000
  ↓
B update fails
  ↓
ROLLBACK
```

The transaction can undo the changes made within that transaction.

---

# 11.18 Pool + Transaction Architecture

Put this in your notes:

```text id="i8f2x8"
                    Node.js
                       │
                       ▼
                Connection Pool
                       │
                    acquire
                       │
                       ▼
                  Connection C1
                       │
                  ┌────┴────┐
                  │         │
                BEGIN      Transaction
                  │         │
                  ├── Query 1
                  ├── Query 2
                  ├── Query 3
                  │
             COMMIT / ROLLBACK
                  │
                  ▼
               release()
                  │
                  ▼
                Pool
```

---

# 11.19 Transaction Connection Occupancy

Imagine:

```text id="5v8j2v"
Pool max = 4
```

At the beginning:

```text id="d0i7cx"
C1 → Idle
C2 → Idle
C3 → Idle
C4 → Idle
```

Transaction A:

```text id="5ah0sl"
C1 → Transaction A
```

Transaction B:

```text id="2l8g0y"
C2 → Transaction B
```

Now:

```text id="iq8v6k"
C1 → Busy
C2 → Busy
C3 → Idle
C4 → Idle
```

Transaction A commits:

```text id="5f4v5d"
C1 → Idle
```

Now another operation can use C1.

The connection only becomes available **after the transaction is finished and the client is released**.

---

# 11.20 Transactions Should Usually Be Short

A useful production principle:

> **Keep transactions as short as reasonably possible.**

Good:

```text id="q4y0be"
BEGIN
 ↓
UPDATE
 ↓
INSERT
 ↓
COMMIT
 ↓
Release
```

Potentially problematic:

```text id="8p1d7y"
BEGIN
 ↓
UPDATE
 ↓
External API call
 ↓
User interaction
 ↓
Heavy computation
 ↓
Another API call
 ↓
INSERT
 ↓
COMMIT
```

The second example can hold a connection for a long time.

That reduces pool availability.

---

# 11.21 Don't Put User Interaction Inside a Transaction

Never design a flow like:

```text id="5c7j9g"
BEGIN
 ↓
Database query
 ↓
Wait for user
 ↓
User responds
 ↓
Database query
 ↓
COMMIT
```

The database connection would remain checked out while waiting.

Instead, structure the application so the transaction covers only the database work that actually needs atomicity.

---

# 11.22 Don't Hold a Connection While Waiting for Unrelated Work

Similarly, avoid:

```text id="1w4q2p"
Acquire connection
 ↓
Query
 ↓
Call external service
 ↓
Wait
 ↓
Another query
 ↓
Release
```

if the external operation doesn't need the database connection.

Prefer, where the business logic allows:

```text id="2y3k0f"
Do independent external work
        ↓
Acquire connection
        ↓
Transaction
        ↓
Queries
        ↓
Commit
        ↓
Release
```

The exact architecture depends on the consistency requirements of the operation.

---

# 11.23 The Golden Transaction Pattern

This is worth memorising:

```js id="1y2z2k"
const client = await pool.connect();

try {
  await client.query("BEGIN");

  // All transaction queries use `client`
  await client.query("...");

  await client.query("...");

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Three things are happening:

### 1. Acquire

```js id="h4j1zz"
const client = await pool.connect();
```

### 2. Keep the same connection

```js id="6zhz3w"
client.query(...)
```

for every transaction statement.

### 3. Release

```js id="8ikq0x"
client.release();
```

after `COMMIT` or `ROLLBACK`.

---

# 11.24 The Transaction Rule

Put this in bold in your README:

> **A PostgreSQL transaction must use the same database connection for all statements belonging to that transaction. When using a connection pool, explicitly acquire one client, perform `BEGIN` → transaction queries → `COMMIT`/`ROLLBACK`, and then release the client back to the pool.**

---

# 11.25 Common Transaction Mistakes

### ❌ Using `pool.query()` for each transaction statement

```js id="x8r0q5"
await pool.query("BEGIN");
await pool.query("UPDATE ...");
await pool.query("INSERT ...");
await pool.query("COMMIT");
```

Don't assume these calls use the same connection.

---

### ❌ Forgetting `client.release()`

```js id="1h5m8w"
const client = await pool.connect();

await client.query("BEGIN");
// ...
await client.query("COMMIT");

// Forgot release
```

Potential connection leak.

---

### ❌ Releasing before the transaction finishes

```js id="xj8m0h"
await client.query("BEGIN");

client.release();

await client.query("UPDATE ...");
```

The connection has already been returned to the pool.

---

### ❌ Holding transactions open unnecessarily

```text id="y8o3n1"
BEGIN
 ↓
5-second API call
 ↓
10-second computation
 ↓
COMMIT
```

This can unnecessarily consume pool capacity.

---

### ❌ Ignoring rollback on failure

```js id="y8w9cj"
catch (error) {
  throw error;
}
```

A transaction should be explicitly rolled back when necessary.

---

# 11.26 Complete Mental Model

```text id="1u2z3x"
                      Node.js
                         │
                         ▼
                  Connection Pool
                         │
                      acquire
                         │
                         ▼
                     Client C1
                         │
                         ▼
                       BEGIN
                         │
                ┌────────┼────────┐
                ▼        ▼        ▼
             Query 1  Query 2  Query 3
                │        │        │
                └────────┼────────┘
                         ▼
                 COMMIT / ROLLBACK
                         │
                         ▼
                    client.release()
                         │
                         ▼
                       Pool
                         │
                         ▼
                   C1 available
```

And the critical relationship is:

```text id="0f9p5m"
Transaction
     ↓
Same connection
     ↓
Connection checked out
     ↓
Pool capacity consumed
     ↓
Transaction completes
     ↓
Connection released
     ↓
Pool capacity available again
```

---

# Key Takeaways

1. A PostgreSQL transaction groups multiple operations into one logical unit.
2. Transaction state belongs to a PostgreSQL session/connection.
3. Therefore, all statements in a transaction must use the **same connection**.
4. With a connection pool, use:

```js id="jq4q3p"
const client = await pool.connect();
```

5. Execute:

```text id="lxr9qn"
BEGIN
 ↓
Queries
 ↓
COMMIT / ROLLBACK
```

on that same `client`.

6. Always return the connection:

```js id="z2o0sl"
client.release();
```

7. Use `finally` so the connection is released even if an error occurs.
8. Don't assume separate `pool.query()` calls belong to the same transaction.
9. Long-running transactions hold connections and can exhaust the pool.
10. Avoid keeping a database connection checked out while waiting for unrelated external work.
11. **Transaction duration directly affects pool availability.**

### The one diagram to remember

```text id="6w3b7d"
Acquire
   ↓
BEGIN
   ↓
Query
   ↓
Query
   ↓
Query
   ↓
COMMIT / ROLLBACK
   ↓
Release
   ↓
Pool
```

> **Transaction + pooling = one connection held temporarily for the entire transaction, then returned to the pool.**

---

# 12. Connection Leaks

Next we'll tackle one of the nastiest real-world pooling problems: **connection leaks**.

We'll see exactly how a forgotten `client.release()` can gradually consume your entire pool, why the application starts hanging, how to write leak-safe code, and how to diagnose leaks in production.

# 12. Connection Leaks

A **connection leak** happens when your application acquires a database connection from the pool but fails to return it.

This is one of the most important production problems to understand because a leak can slowly turn a healthy application into one where **database requests start hanging or timing out**.

---

## 12.1 What Is a Connection Leak?

Suppose your pool has:

```js
const pool = new Pool({
  max: 10
});
```

You acquire a connection:

```js
const client = await pool.connect();
```

Now you've taken one connection out of the pool.

When you're finished, you must return it:

```js
client.release();
```

If you forget:

```js
const client = await pool.connect();

await client.query("SELECT * FROM users");

// ❌ Forgot client.release()
```

that connection remains checked out.

That's a **connection leak**.

---

## 12.2 What Does a Leak Look Like?

Think of the pool as a parking lot.

```text
Pool capacity = 5

[ C1 ] [ C2 ] [ C3 ] [ C4 ] [ C5 ]
```

Initially:

```text
C1 → Idle
C2 → Idle
C3 → Idle
C4 → Idle
C5 → Idle
```

Request 1 acquires C1 but forgets to release it:

```text
C1 → Leaked
C2 → Idle
C3 → Idle
C4 → Idle
C5 → Idle
```

Request 2 leaks C2:

```text
C1 → Leaked
C2 → Leaked
C3 → Idle
C4 → Idle
C5 → Idle
```

Eventually:

```text
C1 → Leaked
C2 → Leaked
C3 → Leaked
C4 → Leaked
C5 → Leaked
```

Now:

```text
Available connections = 0
```

The pool is effectively exhausted.

---

# 12.3 What Happens to the Next Request?

Suppose:

```text
max = 5
```

and all five connections are checked out.

A new query arrives:

```text
Request
   ↓
Pool
   ↓
No idle connection
   ↓
Pool already at max
   ↓
Wait
```

The request may sit in the pool's waiting queue until a connection becomes available or a relevant timeout occurs.

But the leaked connections aren't coming back.

So you can get:

```text
Connection leaks
       ↓
Pool exhaustion
       ↓
Requests waiting
       ↓
Increasing latency
       ↓
Timeouts/errors
```

---

# 12.4 The Dangerous Thing About Leaks

The scary part is that the application might **work perfectly at first**.

Imagine:

```text
Pool max = 10
```

Your application receives requests.

Each request leaks one connection.

```text
Request 1 → 1 leaked
Request 2 → 2 leaked
Request 3 → 3 leaked
...
Request 10 → 10 leaked
```

Only after enough requests does the problem become obvious.

So you might see:

```text
Application starts normally
        ↓
Traffic increases
        ↓
Connections gradually disappear from pool availability
        ↓
Database requests become slower
        ↓
Requests start waiting
        ↓
Timeouts
        ↓
Application appears "stuck"
```

That's why connection leaks can be surprisingly difficult to diagnose.

---

# 12.5 The Most Common Cause

The classic mistake is:

```js
const client = await pool.connect();

await client.query("SELECT ...");

client.release();
```

This looks fine.

But what if the query throws?

```js
const client = await pool.connect();

await client.query("SELECT ..."); // ❌ throws

client.release(); // never reached
```

JavaScript immediately leaves the function because of the exception.

Therefore:

```text
client.release()
```

never executes.

You've leaked the connection.

---

# 12.6 The Correct Pattern: `finally`

This is why we use:

```js
const client = await pool.connect();

try {
  await client.query("SELECT * FROM users");
} finally {
  client.release();
}
```

Why `finally`?

Because `finally` runs whether the operation succeeds or throws.

Conceptually:

```text
              acquire
                 ↓
              execute
              /     \
         success    error
            \         /
             \       /
              finally
                 ↓
              release
```

That's the important pattern.

---

# 12.7 With Transactions

For transactions, the standard pattern becomes:

```js
const client = await pool.connect();

try {
  await client.query("BEGIN");

  await client.query("UPDATE ...");

  await client.query("INSERT ...");

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Notice the responsibilities:

| Responsibility    | Code               |
| ----------------- | ------------------ |
| Acquire           | `pool.connect()`   |
| Start transaction | `BEGIN`            |
| Perform work      | `client.query()`   |
| Success           | `COMMIT`           |
| Failure           | `ROLLBACK`         |
| Return connection | `client.release()` |

---

# 12.8 `pool.query()` Usually Avoids This Particular Mistake

Consider:

```js
const result = await pool.query(
  "SELECT * FROM users WHERE id = $1",
  [userId]
);
```

You aren't manually acquiring a client.

The pool handles the connection lifecycle for that query.

Conceptually:

```text
pool.query()
    ↓
Acquire
    ↓
Execute
    ↓
Release
    ↓
Return result
```

That's one reason `pool.query()` is convenient for ordinary independent queries.

You don't have to manually remember:

```js
client.release();
```

---

# 12.9 When You Use `pool.connect()`, You Own the Release Responsibility

This is an excellent rule to remember:

> **If you manually acquire a client with `pool.connect()`, your code is responsible for releasing it.**

For example:

```js
const client = await pool.connect();

try {
  // work
} finally {
  client.release();
}
```

Think of:

```js
pool.connect()
```

as:

> "I'm borrowing a database connection."

And:

```js
client.release()
```

as:

> "I'm returning the connection."

---

# 12.10 Connection Leak vs Connection Failure

These are different problems.

### Connection leak

Your application keeps a healthy connection checked out and doesn't return it.

```text
Application
    ↓
Acquire C1
    ↓
Use C1
    ↓
❌ Never release
```

### Connection failure

The actual database connection becomes unusable because of a network/database/server problem.

```text
Application
    ↓
Connection
    ↓
Network/database failure
    ↓
Connection becomes unusable
```

A pool implementation can handle broken connections differently from leaked connections.

The key distinction:

> **A leaked connection is usually an application lifecycle bug.**

---

# 12.11 Connection Leak vs Slow Query

These can look similar from the outside.

### Slow query

```text
Acquire
 ↓
Query takes 10 seconds
 ↓
Release
```

The connection is eventually returned.

### Connection leak

```text
Acquire
 ↓
Query completes
 ↓
❌ Never release
```

The connection stays checked out indefinitely unless something else eventually cleans it up.

---

# 12.12 Connection Leak vs Long Transaction

Also distinguish:

### Long transaction

```text
Acquire
 ↓
BEGIN
 ↓
Long work
 ↓
COMMIT
 ↓
Release
```

The connection is occupied for a long time, but eventually comes back.

### Leak

```text
Acquire
 ↓
Work
 ↓
❌ Never release
```

A long transaction is a **duration problem**.

A leak is a **lifecycle problem**.

Both can cause pool exhaustion.

---

# 12.13 How a Pool Gets Exhausted

There are several ways:

```text
                     Pool Exhaustion
                           │
          ┌────────────────┼────────────────┐
          ↓                ↓                ↓
   Connection leaks   Long transactions   Slow queries
          │                │                │
          ↓                ↓                ↓
     Never return     Hold connections    Hold connections
          │                │                │
          └────────────────┼────────────────┘
                           ↓
                  No connections available
                           ↓
                    Requests wait/fail
```

This distinction becomes very useful when debugging production issues.

---

# 12.14 A Realistic Express Example

Suppose:

```js
app.get("/users/:id", async (req, res) => {
  const client = await pool.connect();

  const result = await client.query(
    "SELECT * FROM users WHERE id = $1",
    [req.params.id]
  );

  client.release();

  res.json(result.rows);
});
```

At first glance, it looks okay.

But there is a problem.

If:

```js
client.query(...)
```

throws, then:

```js
client.release();
```

never executes.

A safer version:

```js
app.get("/users/:id", async (req, res, next) => {
  const client = await pool.connect();

  try {
    const result = await client.query(
      "SELECT * FROM users WHERE id = $1",
      [req.params.id]
    );

    res.json(result.rows);
  } catch (error) {
    next(error);
  } finally {
    client.release();
  }
});
```

Now the release happens even when the query fails.

---

# 12.15 Another Important Mistake

Be careful with early returns.

This is dangerous:

```js
const client = await pool.connect();

try {
  const result = await client.query("SELECT ...");

  if (result.rows.length === 0) {
    return [];
  }

  return result.rows;
} finally {
  client.release();
}
```

This version is actually safe because `finally` still runs.

But this version is dangerous:

```js
const client = await pool.connect();

const result = await client.query("SELECT ...");

if (result.rows.length === 0) {
  return [];
}

client.release();
```

The early return means:

```text
return []
  ↓
client.release() never executes
```

Again:

**`finally` protects you from this class of mistake.**

---

# 12.16 Don't Release Twice

You also shouldn't do:

```js
try {
  await client.query("SELECT ...");
  client.release();
} finally {
  client.release(); // ❌
}
```

You should have one clear ownership path:

```js
try {
  await client.query("SELECT ...");
} finally {
  client.release();
}
```

Keep resource ownership simple.

---

# 12.17 Don't Keep a Client in Global Mutable State

Avoid patterns like:

```js
let client;

app.get("/users", async () => {
  client = await pool.connect();
});
```

A shared mutable client can create concurrency and lifecycle problems.

The pool is designed to manage multiple connections.

Normally, acquire a client for the operation that needs it:

```js
const client = await pool.connect();

try {
  // use client
} finally {
  client.release();
}
```

---

# 12.18 How to Think About Ownership

A useful programming concept here is **resource ownership**.

When you do:

```js
const client = await pool.connect();
```

your code temporarily owns the right to use that pooled connection.

Therefore:

```text
Acquire
   ↓
Ownership
   ↓
Use
   ↓
Release ownership
```

You should be able to look at your code and answer:

> **Who is responsible for releasing this connection?**

If the answer isn't obvious, your resource management is probably too messy.

---

# 12.19 Connection Leaks in Production

Imagine:

```text
max = 20
```

Normally:

```text
Active = 5
Idle = 15
Waiting = 0
```

Everything is healthy.

Then a bug starts leaking connections:

```text
Active/checked-out = 10
Idle = 10
```

Later:

```text
Active/checked-out = 15
Idle = 5
```

Later:

```text
Active/checked-out = 20
Idle = 0
Waiting = 8
```

Now the pool is saturated.

Eventually:

```text
Requests
   ↓
Waiting for connections
   ↓
Timeouts
```

The database itself might still be perfectly capable of executing queries.

The problem is that your application has **lost access to its available pool connections**.

---

# 12.20 A Very Important Debugging Insight

If you see:

```text
Database is healthy
BUT
Application database requests are hanging
```

don't immediately conclude:

> "PostgreSQL is slow."

Investigate:

```text
Pool usage
↓
Waiting requests
↓
Long-running queries
↓
Long transactions
↓
Connection leaks
```

The bottleneck might be **between your Node.js application and PostgreSQL**, specifically the connection pool.

---

# 12.21 Prevention Checklist

Whenever you manually use:

```js
pool.connect()
```

ask:

* Did I release the client?
* Does release happen if the query throws?
* Does release happen if I return early?
* Does release happen after `COMMIT`?
* Does release happen after `ROLLBACK`?
* Is release inside `finally`?
* Am I unnecessarily holding the connection while doing other work?

If you can answer these correctly, you're already avoiding many pooling bugs.

---

# 12.22 The Golden Pattern

For a normal operation requiring explicit connection control:

```js
const client = await pool.connect();

try {
  // database work
} finally {
  client.release();
}
```

For a transaction:

```js
const client = await pool.connect();

try {
  await client.query("BEGIN");

  // transaction work

  await client.query("COMMIT");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  client.release();
}
```

Memorise these two patterns.

---

# 12.23 Mental Model

```text
pool.connect()
      ↓
   Borrow
      ↓
    Client
      ↓
    Work
      ↓
   Release
      ↓
   Pool
```

Leak:

```text
pool.connect()
      ↓
   Borrow
      ↓
    Client
      ↓
    Work
      ↓
      ❌
   No release
      ↓
Connection unavailable to pool
```

Repeated enough times:

```text
Leak
 ↓
Leak
 ↓
Leak
 ↓
Leak
 ↓
Pool exhausted
 ↓
Requests wait
 ↓
Timeouts
```

---

# Key Takeaways

1. A **connection leak** occurs when an acquired connection isn't returned to the pool.
2. `pool.connect()` creates a responsibility to release the client.
3. Use `finally` to make release reliable.
4. `pool.query()` is convenient because you don't manually manage the acquired client.
5. Connection leaks can gradually exhaust the entire pool.
6. Pool exhaustion can cause requests to wait or eventually fail.
7. A leak is different from a slow query or a long transaction.
8. Long transactions can still contribute to pool exhaustion because they hold connections.
9. Don't hold a connection while doing unrelated slow work.
10. For transactions, use:

```text
BEGIN → queries → COMMIT/ROLLBACK → release
```

11. **Every manually acquired client should have a clear release path.**

### The rule to burn into your brain 🔥

> **If you `pool.connect()`, you must eventually `client.release()`. Put the release in `finally`.**

---

## 13. Pool Timeout Settings

Next we'll look at the timeout controls that prevent your application from waiting forever—especially **`connectionTimeoutMillis`**, **`idleTimeoutMillis`**, and what happens when a pool is saturated.

# 13. Pool Timeout Settings

Timeouts are what prevent your application from **waiting indefinitely** when PostgreSQL or the connection pool isn't responding as expected.

For `node-postgres` (`pg`), several timeout-related settings matter, but they control **different stages of the connection lifecycle**.

The big ones to understand are:

```text
connectionTimeoutMillis
idleTimeoutMillis
```

And you should also understand the difference between:

```text
Connection timeout
Query timeout
Pool waiting
```

These are **not the same thing**.

---

# 13.1 Why Do We Need Timeouts?

Imagine your application has:

```text
Pool max = 10
```

and all 10 connections are busy:

```text
C1 → Busy
C2 → Busy
C3 → Busy
...
C10 → Busy
```

A new request arrives.

There is no connection available.

So:

```text
Request
   ↓
Pool
   ↓
No connection available
   ↓
Wait
```

Without appropriate safeguards, something could potentially sit waiting much longer than you want.

Timeouts give your application a way to say:

> "If this operation takes too long, stop waiting and fail."

This is important for production systems because **waiting forever is usually worse than failing fast**.

---

# 13.2 `connectionTimeoutMillis`

In `pg`, you can configure:

```js
const pool = new Pool({
  connectionTimeoutMillis: 2000
});
```

This controls how long the client is allowed to wait while establishing a connection before timing out.

In simple terms:

```text
Application
    ↓
Attempt to establish PostgreSQL connection
    ↓
Wait
    ↓
Timeout if connection establishment takes too long
```

For example:

```js
connectionTimeoutMillis: 2000
```

means approximately:

```text
2 seconds
```

for connection establishment.

---

# 13.3 What `connectionTimeoutMillis` Does NOT Mean

This is extremely important.

It does **not** mean:

> "Every database query has a 2-second timeout."

For example:

```js
const pool = new Pool({
  connectionTimeoutMillis: 2000
});
```

doesn't automatically mean:

```text
SELECT query
 ↓
2 seconds
 ↓
Automatically cancelled
```

That's a different concern.

So don't confuse:

```text
Connection timeout
```

with:

```text
Query timeout
```

---

# 13.4 Query Timeout Is Different

Suppose a connection has already been established:

```text
Node.js
   ↓
Connected
   ↓
PostgreSQL
```

Then you execute:

```sql
SELECT ...
```

The query itself might take a long time.

A query timeout is about:

```text
Query started
     ↓
Query running
     ↓
Too much time
     ↓
Cancel/fail according to configured mechanism
```

That's different from:

```text
Trying to establish connection
     ↓
Cannot connect
     ↓
Connection timeout
```

---

# 13.5 Three Different Waiting Problems

A useful mental model is:

```text
                    Database Operation
                           │
            ┌──────────────┼──────────────┐
            ↓              ↓              ↓
      Get connection   Establish       Execute query
       from pool       connection
            │              │              │
            ↓              ↓              ↓
       Pool waiting   Connection       Query
                      timeout          timeout
```

These are separate stages.

---

# 13.6 `idleTimeoutMillis`

Now the other important setting:

```js
const pool = new Pool({
  idleTimeoutMillis: 10000
});
```

This controls how long an **idle pooled connection** can remain unused before the pool closes it, subject to the pool's behaviour and lifecycle rules.

For example:

```text
Connection C1
     ↓
Query finishes
     ↓
C1 becomes idle
     ↓
No work arrives
     ↓
Idle timeout
     ↓
Connection closed
```

This helps prevent the application from keeping unnecessary idle connections around indefinitely.

---

# 13.7 Idle Does NOT Mean Dead

This is an important distinction.

Suppose:

```text
C1 → Idle
```

It means:

> C1 is connected and available for reuse.

It does **not** mean:

> C1 has been disconnected.

So:

```text
Idle connection
```

is still a real PostgreSQL connection.

The pool may later reuse it:

```text
Idle
 ↓
New query
 ↓
Reuse
 ↓
Busy
```

---

# 13.8 Why Idle Connections Matter

Suppose your application has:

```text
max = 20
```

but current workload only needs:

```text
3 connections
```

You might have:

```text
C1 → Busy
C2 → Idle
C3 → Idle
```

Idle connections consume resources even though they aren't currently executing queries.

That's why pools can have policies for closing idle connections.

The trade-off is:

```text
Keep idle connections
        ↓
Faster reuse
        +
More resources consumed
```

versus:

```text
Close idle connections
        ↓
Fewer resources
        +
Potential connection establishment overhead later
```

---

# 13.9 `idleTimeoutMillis` vs `connectionTimeoutMillis`

This comparison is worth memorising:

| Setting                   | Controls                                             |
| ------------------------- | ---------------------------------------------------- |
| `connectionTimeoutMillis` | How long establishing a connection may take          |
| `idleTimeoutMillis`       | How long an idle pooled connection may remain unused |

Think:

```text
connectionTimeoutMillis
        ↓
"Can I establish a connection?"

idleTimeoutMillis
        ↓
"How long should this unused connection stay around?"
```

---

# 13.10 What Happens When the Pool Is Full?

This is where things get interesting.

Suppose:

```js
const pool = new Pool({
  max: 5
});
```

All five connections are busy:

```text
C1 → Busy
C2 → Busy
C3 → Busy
C4 → Busy
C5 → Busy
```

Then:

```js
await pool.query("SELECT ...");
```

arrives.

There isn't an idle connection.

The pool cannot exceed:

```text
max = 5
```

So the operation has to wait for a connection to become available.

Conceptually:

```text
Request 6
    ↓
Pool
    ↓
No idle connections
    ↓
Pool at max
    ↓
Waiting
```

---

# 13.11 Pool Waiting Is Not the Same as Connection Establishment

This distinction is subtle but **very important**.

Suppose:

```text
Pool max = 10
```

and all ten connections are already established and busy.

Request 11 waits.

That's:

```text
Pool acquisition waiting
```

It is **not necessarily**:

```text
Trying to establish a new PostgreSQL connection
```

The pool is already at its configured maximum.

So don't automatically interpret:

```text
Request waiting for pool
```

as:

> "PostgreSQL connection establishment is timing out."

Different problem.

---

# 13.12 Example

Imagine:

```text
max = 3
```

Current state:

```text
C1 → Busy
C2 → Busy
C3 → Busy
```

Request D:

```text
D → Waiting
```

Then C2 finishes:

```text
C1 → Busy
C2 → Idle
C3 → Busy
```

Request D can now acquire C2:

```text
C1 → Busy
C2 → D
C3 → Busy
```

The waiting request doesn't necessarily create another connection.

It uses the connection that became available.

---

# 13.13 Why Pool Saturation Is Important

Suppose you see:

```text
Active connections = max
Waiting requests = many
```

That tells you something useful:

> **Your pool is saturated.**

But don't immediately conclude:

> "Increase `max`."

The real cause might be:

```text
Slow SQL
Long transactions
Database contention
Connection leaks
External work while holding clients
Too much application concurrency
Pool configured too small
```

Increasing the pool is only one possible response.

---

# 13.14 The "Just Increase the Pool" Trap

Imagine:

```text
max = 10
```

and your requests are slow because a query takes:

```text
5 seconds
```

You increase:

```text
max = 50
```

Now you have many more concurrent database operations.

But if PostgreSQL is already struggling, you may make things worse.

You can end up with:

```text
More connections
      ↓
More concurrent work
      ↓
More DB contention
      ↓
Higher latency
```

So:

> **Pool size and timeout settings should be based on workload and database capacity, not guessed independently.**

---

# 13.15 Timeouts Are Part of Backpressure

Connection pools provide a form of **backpressure**.

Suppose your application can generate:

```text
1000 concurrent DB operations
```

but your database can safely handle only a smaller amount of concurrent work.

The pool can limit the number of simultaneous connections:

```text
1000 requests
      ↓
Pool
      ↓
Only max connections execute DB work concurrently
      ↓
Others wait
```

This prevents your application from opening an unlimited number of database connections.

Timeouts then prevent waiting from continuing indefinitely.

---

# 13.16 A Practical Configuration

A basic `pg` pool might look like:

```js
const pool = new Pool({
  max: 10,
  connectionTimeoutMillis: 2000,
  idleTimeoutMillis: 30000
});
```

Conceptually:

```text
max = 10
     ↓
At most 10 pooled connections

connectionTimeoutMillis = 2000
     ↓
Connection establishment timeout around 2 seconds

idleTimeoutMillis = 30000
     ↓
Unused idle connections can be closed after around 30 seconds
```

These values are **examples**, not universal production recommendations.

---

# 13.17 Don't Blindly Copy Timeout Values

You might see someone write:

```js
connectionTimeoutMillis: 1000
```

and think:

> "One second must be the best setting."

No.

The correct value depends on:

* network latency
* whether DB is local or remote
* cloud architecture
* database load
* failover behaviour
* application requirements
* expected request latency

For example:

```text
Node.js → same machine → PostgreSQL
```

has very different characteristics from:

```text
Node.js → internet/private network → managed PostgreSQL
```

---

# 13.18 Timeouts and User Experience

Imagine an HTTP endpoint:

```text
GET /users
```

If the database becomes unavailable and your server waits indefinitely:

```text
Browser
   ↓
HTTP request
   ↓
Node.js
   ↓
Database
   ↓
Waiting...
   ↓
Waiting...
   ↓
Waiting...
```

That's terrible for the user.

A bounded timeout allows:

```text
Request
   ↓
Database unavailable
   ↓
Timeout
   ↓
Error handling
   ↓
HTTP error response
```

Your application can then fail in a controlled way.

---

# 13.19 But Don't Confuse DB Timeout With HTTP Timeout

You can have multiple timeout layers:

```text
Client
   ↓
HTTP timeout
   ↓
Node.js
   ↓
Pool/connection timeout
   ↓
PostgreSQL
   ↓
Query timeout
```

For example:

```text
Browser timeout
    ≠
Node request timeout
    ≠
Pool wait
    ≠
Connection timeout
    ≠
SQL query timeout
```

A production backend often needs to think about these independently.

---

# 13.20 Pool Timeout Mental Model

Remember this flow:

```text
                Request
                   │
                   ▼
             Need DB work
                   │
                   ▼
            Connection Pool
                   │
          ┌────────┴────────┐
          │                 │
     Idle available     No idle
          │                 │
          ▼                 ▼
       Acquire          Pool at max?
                            │
                      ┌─────┴─────┐
                     No          Yes
                      │            │
                      ▼            ▼
                  Create       Wait
                  connection
                      │            │
                      └─────┬──────┘
                            ▼
                         Execute
                            │
                            ▼
                         Release
```

Timeouts can apply at different points in this lifecycle.

---

# 13.21 Important `pg` Settings to Know

For connection pooling, know these concepts:

### `max`

Maximum number of clients/connections in the pool.

```js
max: 10
```

---

### `idleTimeoutMillis`

How long an idle client can remain before being closed.

```js
idleTimeoutMillis: 30000
```

---

### `connectionTimeoutMillis`

Maximum time allowed when establishing a connection.

```js
connectionTimeoutMillis: 2000
```

---

There are also additional settings and PostgreSQL-level timeout mechanisms, but these three are enough to establish the core pool model at this stage.

---

# 13.22 PostgreSQL Has Its Own Timeout Settings

This is another layer.

PostgreSQL itself has timeout-related settings, such as:

```sql
statement_timeout
```

which controls how long statements are allowed to run before PostgreSQL cancels them.

You can think of it as:

```text
Node.js pool
     │
     ├── Connection lifecycle settings
     │
     ▼
PostgreSQL
     │
     ├── Statement execution limits
     └── Other server-side timeout policies
```

So your application timeout configuration and PostgreSQL timeout configuration are related but **not the same thing**.

---

# 13.23 Why This Matters for Backend Engineers

When debugging a production request that takes 10 seconds, don't just ask:

> "Why is PostgreSQL slow?"

Ask:

```text
1. Did the request wait for a pool connection?
2. Was a new connection being established?
3. How long did connection establishment take?
4. How long did the SQL query execute?
5. Was the transaction unusually long?
6. Was the connection leaked?
7. Was PostgreSQL itself overloaded?
8. Did some upstream/downstream timeout occur first?
```

This is how you move from:

> "Database is slow."

to:

> "The request spent 4.2 seconds waiting for a pooled connection and only 200 ms executing SQL."

That is a **much more useful diagnosis**.

---

# 13.24 Production Debugging Example

Suppose you observe:

```text
HTTP latency = 8 seconds
```

You investigate and discover:

```text
Pool max = 10
Busy = 10
Waiting = 30
```

Then you discover:

```text
Average query execution = 100 ms
```

The query itself isn't taking 8 seconds.

Instead:

```text
Request
   ↓
Wait for pool connection = ~7.8 sec
   ↓
Query = ~0.2 sec
```

The actual bottleneck is pool saturation.

This distinction is **huge**.

---

# 13.25 Key Difference: Idle Timeout vs Leak

Don't confuse these.

### Idle timeout

```text
Connection
   ↓
Idle
   ↓
Unused for configured period
   ↓
Pool closes it
```

That's normal pool behaviour.

### Leak

```text
Connection
   ↓
Checked out
   ↓
Application forgets release()
   ↓
Never becomes available to pool
```

That's an application bug.

---

# 13.26 The Complete Picture

```text
                 Node.js Application
                         │
                         ▼
                  Connection Pool
                         │
              ┌──────────┼──────────┐
              │          │          │
             max     idle timeout  connection
                                  timeout
              │          │          │
              ▼          ▼          ▼
         Capacity     Cleanup    Establishment
              │
              ▼
        Pool saturation
              │
              ▼
           Waiting
              │
              ▼
          Latency
              │
              ▼
           Timeout
```

And separately:

```text
PostgreSQL
    │
    └── statement_timeout
             ↓
       Query execution limit
```

---

# Key Takeaways

1. **Timeouts protect your application from waiting indefinitely.**
2. `connectionTimeoutMillis` concerns **establishing a PostgreSQL connection**.
3. `idleTimeoutMillis` concerns **unused idle pooled connections**.
4. Neither one means "every SQL query has this timeout."
5. Pool waiting and connection establishment are different things.
6. When the pool reaches `max`, new work may have to wait for an existing connection to be released.
7. Pool saturation can come from:

   * slow queries
   * long transactions
   * connection leaks
   * excessive concurrency
   * an undersized pool
8. Don't blindly increase `max` when the pool is saturated.
9. PostgreSQL has its own timeout mechanisms, such as `statement_timeout`.
10. In production, distinguish:

```text
Pool wait
≠
Connection establishment
≠
Query execution
```

11. A useful debugging question is:

> **Where exactly did the request spend its time?**

### Mental model

```text
Need DB
   ↓
Get connection
   ↓
[connection timeout applies to establishment]
   ↓
Execute SQL
   ↓
[query/server timeout may apply here]
   ↓
Release
   ↓
Connection becomes idle
   ↓
[idle timeout may eventually close it]
```

---

## 14. PostgreSQL's `max_connections`

Next, we'll move from the **Node.js pool layer** to the **PostgreSQL server layer**.

This is where you'll understand what `max_connections` actually means, why having `pg` pools of `max: 20` doesn't mean PostgreSQL can magically handle unlimited connections, and why your **application pool size must be planned together with PostgreSQL's connection limit**.
