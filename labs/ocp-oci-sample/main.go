package main
import (
	"context"
	"fmt"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/identity"

	//"crypto/tls"
	//"crypto/x509"
	"log"
	//"net/http"

	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/example/helpers"
)

func mainDefault() {
	c, err := identity.NewIdentityClientWithConfigurationProvider(common.DefaultConfigProvider())
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	// The OCID of the tenancy containing the compartment.
	tenancyID, err := common.DefaultConfigProvider().TenancyOCID()
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	request := identity.ListAvailabilityDomainsRequest{
		CompartmentId: &tenancyID,
	}

	r, err := c.ListAvailabilityDomains(context.Background(), request)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	fmt.Printf("List of available domains: %v", r.Items)
	return
}

func mainIP() {

	provider, err := auth.InstancePrincipalConfigurationProvider()
	helpers.FatalIfError(err)

	tenancyID := helpers.RootCompartmentID()
	request := identity.ListAvailabilityDomainsRequest{
		CompartmentId: tenancyID,
	}

	client, err := identity.NewIdentityClientWithConfigurationProvider(provider)
	// Override the region, this is an optional step.
	// the InstancePrincipalsConfigurationProvider defaults to the region
	// in which the compute instance is currently running
	client.SetRegion(string(common.RegionLHR))

	r, err := client.ListAvailabilityDomains(context.Background(), request)
	helpers.FatalIfError(err)

	log.Printf("list of available domains: %v", r.Items)
	fmt.Println("Done")

	// Output:
	// Done
}

func main() {
  mainIP()
}
