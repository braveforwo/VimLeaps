package binder

import (
	"os"

	"leaps/lib/util/service/log"
)

func loggerAndStats() log.Modular {
	logConf := log.NewLoggerConfig()
	logConf.LogLevel = "OFF"

	logger := log.NewLogger(os.Stdout, logConf)
	// stats := metrics.DudType{}

	return logger
}
