/*
Copyright (c) 2014 Ashley Jeffs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, sub to the following conditions:

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

package acl

import (
	"os"
	"testing"

	"leaps/lib/util/service/log"
)

//--------------------------------------------------------------------------------------------------

func logger() log.Modular {
	logConf := log.NewLoggerConfig()
	logConf.LogLevel = "OFF"
	return log.NewLogger(os.Stdout, logConf)
}

func TestIgnorePatterns(t *testing.T) {
	f := FileExists{logger: logger()}

	testStories := []struct {
		Patterns []string
		Path     string
		Expected bool
	}{
		{
			Patterns: []string{"*.jpg"},
			Path:     "test.jpg",
			Expected: true,
		},
		{
			Patterns: []string{"*.jpg"},
			Path:     "./test.jpg",
			Expected: true,
		},
		{
			Patterns: []string{"./*.jpg"},
			Path:     "foo/test.jpg",
			Expected: false,
		},
		{
			Patterns: []string{"./*.jpg"},
			Path:     "test.jpg",
			Expected: true,
		},
		{
			Patterns: []string{"*.jpg"},
			Path:     "foo/test.jpg",
			Expected: true,
		},
		{
			Patterns: []string{"foo/*.jpg"},
			Path:     "foo/test.jpg",
			Expected: true,
		},
		{
			Patterns: []string{"foo/*.jpg"},
			Path:     "test.jpg",
			Expected: false,
		},
		{
			Patterns: []string{"foo/**/*.jpg"},
			Path:     "test.jpg",
			Expected: false,
		},
	}

	for _, story := range testStories {
		exp, act := story.Expected, f.checkPatterns(story.Patterns, story.Path)
		if exp != act {
			t.Errorf("Wrong result: %v != %v\n", exp, act)
			t.Errorf("Patterns: %s\n", story.Patterns)
			t.Errorf("Path:     %s\n", story.Path)
		}
	}
}

//--------------------------------------------------------------------------------------------------
