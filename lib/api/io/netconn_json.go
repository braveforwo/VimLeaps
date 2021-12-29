package io

import (
	"encoding/json"
	"io"
	"net"
)

type NetConn struct {
	Conn net.Conn
}

func (c *NetConn) ReadJSON(v interface{}) error {
	err := json.NewDecoder(c.Conn).Decode(v)
	if err == io.EOF {
		err = io.ErrUnexpectedEOF
	}
	return err
}

func BytesToUin32(b []byte) uint32 {
	_ = b[3]
	return uint32(b[0]) | uint32(b[1])<<8 | uint32(b[2])<<16 | uint32(b[3])<<24
}

func (c *NetConn) WriteJSON(v interface{}) error {
	return json.NewEncoder(c.Conn).Encode(v)
}

func (c *NetConn) Close() error {
	return c.Conn.Close()
}
