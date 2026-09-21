package parity

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestParity(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "parity suite")
}
