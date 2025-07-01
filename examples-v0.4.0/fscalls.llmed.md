<!--
#% show the current freeswitch calls
#% 2025-06-30 i don't know how to describe the protocol :(
#!environment language ruby
#!environment output_file fscalls.rb
-->

# Dependencies

* Use standard library.
* Use library `table_print`.

# Protocol Freeswitch

Parse the input packet as string into a data structure, example:

```
<Header1>: <Value1>
<Header2>: <Value2>

```

become
```
{Header1: Value1, Header2: Value2}
```

There are two types the packets:
1. fixed packet
2. dynamic packet

## fixed packet

example input

```
Content-Type: command/reply
Reply-Text: +OK accepted
```

expected data structure

```
{content-type: 'command/reply', reply-text: '+OK accepted'}
```

## dynamic packet

a dynamic packet is in two phases:
1. a fixed packet
2. ask for more bytes.


example input

```
Content-Type: api/response
Content-Length: 884

"row_count":1,"rows":[{"uuid":"0843f5c8-a736-464c-af5f-530359ec1fc3","direction":"inbound","created":"2025-06-30 11:03:53","created_epoch":"1751281433","name":"sofia/internal/1000@172.15.238.10","state":"CS_EXECUTE","cid_name":"1000","cid_num":"1000","ip_addr":"172.15.238.1","dest":"9196","presence_id":"1000@172.15.238.10","presence_data":"","accountcode":"1000","callstate":"ACTIVE","callee_name":"","callee_num":"","callee_direction":"","call_uuid":"","hostname":"ee69df2f99e3","sent_callee_name":"","sent_callee_num":"","b_uuid":"","b_direction":"","b_created":"","b_created_epoch":"","b_name":"","b_state":"","b_cid_name":"","b_cid_num":"","b_ip_addr":"","b_dest":"","b_presence_id":"","b_presence_data":"","b_accountcode":"","b_callstate":"","b_callee_name":"","b_callee_num":"","b_callee_direction":"","b_sent_callee_name":"","b_sent_callee_num":"","call_created_epoch":""}]
```

after getting the fixed packet, fetch the bytes indicated by the key `content-length`, generating the data structure

```
{'content-type': 'api/response', 'content-length': 884, 'content': `{"row_count":1,"rows":[{"uuid":"0843f5c8-a736-464c-af5f-530359ec1fc3","direction":"inbound","created":"2025-06-30 11:03:53","created_epoch":"1751281433","name":"sofia/internal/1000@172.15.238.10","state":"CS_EXECUTE","cid_name":"1000","cid_num":"1000","ip_addr":"172.15.238.1","dest":"9196","presence_id":"1000@172.15.238.10","presence_data":"","accountcode":"1000","callstate":"ACTIVE","callee_name":"","callee_num":"","callee_direction":"","call_uuid":"","hostname":"ee69df2f99e3","sent_callee_name":"","sent_callee_num":"","b_uuid":"","b_direction":"","b_created":"","b_created_epoch":"","b_name":"","b_state":"","b_cid_name":"","b_cid_num":"","b_ip_addr":"","b_dest":"","b_presence_id":"","b_presence_data":"","b_accountcode":"","b_callstate":"","b_callee_name":"","b_callee_num":"","b_callee_direction":"","b_sent_callee_name":"","b_sent_callee_num":"","call_created_epoch":""}]}`}
```

# Protocol Client

Implement the Protocol Freeswitch on top a TCP Connection.

Considerations after opening a tcp connection:
1. Send `auth <password>\n\n`.
2. Wait for fixed packet of `content-type` `command/reply`

When a command is requested:
1. Write to connection `<command>\n\n`.
2. Wait for fixed packet or dynamic packet.

# Main

- Use Protocol Client to connect to server 172.15.238.10:8021 and authenticate with password 'ClueCon'.
- Protocol Client execute `api show calls as json` parse the json response, extract the columns: cid_name,cdi_num,direction and show in a tabulated table.
