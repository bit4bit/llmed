<!--
#% show the current freeswitch calls
#% 2025-06-30 i don't know how to describe the protocol :(
#!environment language ruby
#!environment output_file fscalls.rb
-->

# Dependencies

* Use standard library.
* Use library `table_print`.

# Protocol

Text TCP-based protocol.

flow in description of examples:

`!<` receive from remote server.
`!>` send to server.

## Protocol Structure

```
<Header>: <Value>
<Header>: <Value>

```

### Content-Type: command/reply

the response is the content of the header `Reply-Text`.

example:
```
!<Content-Type: auth/request
!<
!>auth ClueCon
!>
!<Content-Type: command/reply
!<Reply-Text: +OK accepted
!<
```
Response is `+OK accepted`

### Content-Type: api/response

To get the response must fetch all the bytes indicated in the header `Content-Length`.

example:
```
!>api show calls as json
!>
!<Content-Type: api/response
!<Content-Length: 884
!<
!<{"row_count":1,"rows":[{"uuid":"0843f5c8-a736-464c-af5f-530359ec1fc3","direction":"inbound","created":"2025-06-30 11:03:53","created_epoch":"1751281433","name":"sofia/internal/1000@172.15.238.10","state":"CS_EXECUTE","cid_name":"1000","cid_num":"1000","ip_addr":"172.15.238.1","dest":"9196","presence_id":"1000@172.15.238.10","presence_data":"","accountcode":"1000","callstate":"ACTIVE","callee_name":"","callee_num":"","callee_direction":"","call_uuid":"","hostname":"ee69df2f99e3","sent_callee_name":"","sent_callee_num":"","b_uuid":"","b_direction":"","b_created":"","b_created_epoch":"","b_name":"","b_state":"","b_cid_name":"","b_cid_num":"","b_ip_addr":"","b_dest":"","b_presence_id":"","b_presence_data":"","b_accountcode":"","b_callstate":"","b_callee_name":"","b_callee_num":"","b_callee_direction":"","b_sent_callee_name":"","b_sent_callee_num":"","call_created_epoch":""}]}
```
Response is `{"row_count":1,"rows":[{"uuid":"0843f5c8-a736-464c-af5f-530359ec1fc3","direction":"inbound","created":"2025-06-30 11:03:53","created_epoch":"1751281433","name":"sofia/internal/1000@172.15.238.10","state":"CS_EXECUTE","cid_name":"1000","cid_num":"1000","ip_addr":"172.15.238.1","dest":"9196","presence_id":"1000@172.15.238.10","presence_data":"","accountcode":"1000","callstate":"ACTIVE","callee_name":"","callee_num":"","callee_direction":"","call_uuid":"","hostname":"ee69df2f99e3","sent_callee_name":"","sent_callee_num":"","b_uuid":"","b_direction":"","b_created":"","b_created_epoch":"","b_name":"","b_state":"","b_cid_name":"","b_cid_num":"","b_ip_addr":"","b_dest":"","b_presence_id":"","b_presence_data":"","b_accountcode":"","b_callstate":"","b_callee_name":"","b_callee_num":"","b_callee_direction":"","b_sent_callee_name":"","b_sent_callee_num":"","call_created_epoch":""}]}`.

### How to Use

Way of use:
- authenticate using command `auth <password>`
- execute command
- wait response of command
- parse response


# Main

- Connect to server 172.15.238.10:8021.
- Execute `api show calls as json` parse the json response, extract the columns: cid_name,cdi_num,direction and show in a tabulated table.
