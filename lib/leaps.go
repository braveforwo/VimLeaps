/*
Copyright (c) 2014 Ashley Jeffs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

package main

import (
	"encoding/json"
	"net"

	"fmt"
	"os"
	"time"

	"leaps/lib/acl"

	"leaps/lib/api"
	apiio "leaps/lib/api/io"
	"leaps/lib/audit"
	"leaps/lib/curator"
	"leaps/lib/store"
	"leaps/lib/util"
	"leaps/lib/util/service/log"
)

//------------------------------------------------------------------------------

type OtConnection struct {
	projectID  string
	username   string
	sessionId  string
	targetPath string
}

func NewOtConnection(projectID, username, sessionId, targetPath string) *OtConnection {
	return &OtConnection{
		projectID:  projectID,
		username:   username,
		sessionId:  sessionId,
		targetPath: targetPath,
	}
}

type ProjectOtBroker struct {
	logger log.Modular
	//stats        metrics.Type
	docStore     store.Type
	curator      *curator.Impl
	globalBroker *api.GlobalMetadataBroker
}

func NewProjectOtBroker(targetPath string) *ProjectOtBroker {
	// Logging and metrics aggregation
	logConf := log.NewLoggerConfig()
	logConf.Prefix = "ot"
	logConf.LogLevel = "TRACE"
	logger := log.NewLogger(os.Stdout, logConf)

	// Document storage engine
	docStore, err := store.NewFile(targetPath, true)
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, fmt.Sprintf("Document store error: %v\n", err))
		os.Exit(1)
	}

	// Authenticator
	authenticator := acl.Anarchy{AllowCreate: true}
	// Auditors
	auditors := audit.NewToJSON()
	// Curator of documents
	curatorConf := curator.NewConfig()
	curator, err := curator.New(curatorConf, logger, authenticator, docStore, auditors)
	if err != nil {
		_, _ = fmt.Fprintln(os.Stderr, fmt.Sprintf("Curator error: %v\n", err))
		os.Exit(1)
	}
	//defer curator.Close()

	// Leaps API
	globalBroker := api.NewGlobalMetadataBroker(time.Second*300, logger)

	return &ProjectOtBroker{
		logger: logger,
		//stats:        stats,
		docStore:     docStore,
		curator:      curator,
		globalBroker: globalBroker,
	}
}

type VimHandshake struct {
	// ProjectID  string `json:"projectid"`
	UserName   string `json:"username"`
	TargetPath string `json:"path"`
}

func StartOtConnection(conn net.Conn) {
	vh := VimHandshake{}
	err := json.NewDecoder(conn).Decode(&vh)
	if err != nil {
		_ = conn.Close()
		fmt.Println("read vim connection error:", err)
		return
	}

	br := NewProjectOtBroker(vh.TargetPath)

	uuid := util.GenerateUUID()

	jsonEmitter := apiio.NewJSONEmitter(&apiio.ConcurrentJSON{C: &apiio.NetConn{Conn: conn}})

	br.globalBroker.NewEmitter(vh.UserName, uuid, jsonEmitter)
	api.NewCuratorSession(vh.UserName, uuid, jsonEmitter, br.curator, time.Second*300, br.logger)
	jsonEmitter.ListenAndEmit()
}

func NewOtServer() {
	var err error

	listener, err := net.Listen("tcp", "0.0.0.0:8332")
	if err != nil {
		fmt.Errorf("listen fail, err: %v\n", err)
		return
	}
	fmt.Println("start listen leaps service: 127.0.0.1:8332")

	for {
		conn, err := listener.Accept()
		if err != nil {
			fmt.Errorf("accept fail, err: %v\n", err)
			continue
		}
		go StartOtConnection(conn)
	}
}

func main() {
	NewOtServer()
}
