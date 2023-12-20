# https://diagrams.mingrammer.com/docs/nodes/aws
from diagrams import Cluster, Diagram, Edge
from diagrams.custom import Custom
from urllib.request import urlretrieve

from diagrams.azure.network import DNSZones

from diagrams.k8s.rbac import (
    ServiceAccount, ClusterRole, ClusterRoleBinding, Group
)

from diagrams.k8s.podconfig import (
    Secret
)

from diagrams.k8s.controlplane import (
    APIServer
)

from diagrams.k8s.compute import (
    Pod
)

from diagrams.k8s.storage import (
    Vol
)

from diagrams.aws.network import (
    CF,
    Privatelink
)

from diagrams.aws.storage import (
    SimpleStorageServiceS3BucketWithObjects,
    SimpleStorageServiceS3Object
)

from diagrams.aws.security  import (
    IdentityAndAccessManagementIamAddOn,
    IdentityAndAccessManagementIamAWSStsAlternate,
    IdentityAndAccessManagementIamTemporarySecurityCredential,
    IAMRole,
    ACM
)

from diagrams.aws.general import (
    GenericSamlToken
)


files_url = "https://icon-library.com/images/file-system-icon/file-system-icon-27.jpg"
files_icon = "/tmp/icon-files.png"
urlretrieve(files_url, files_icon)

api_url = "https://icon-library.com/images/api-icon/api-icon-3.jpg"
api_icon = "/tmp/icon-api.png"
urlretrieve(api_url, api_icon)

openshift_url = "https://upload.wikimedia.org/wikipedia/commons/3/3a/OpenShift-LogoType.svg"
openshift_icon = "/tmp/icon-openshift.png"
urlretrieve(openshift_url, openshift_icon)

k8s_url = "https://upload.wikimedia.org/wikipedia/commons/3/39/Kubernetes_logo_without_workmark.svg"
k8s_icon = "/tmp/icon-k8s.png"
urlretrieve(k8s_url, k8s_icon)

aws_url = "https://upload.wikimedia.org/wikipedia/commons/5/5c/AWS_Simple_Icons_AWS_Cloud.svg"
aws_icon = "/tmp/icon-aws.png"
urlretrieve(aws_url, aws_icon)

gcp_url = "https://dt-cdn.net/images/google-cloud-platform-signet-5f2c2ccf7d.svg"
gcp_icon = "/tmp/icon-gcp.png"
urlretrieve(gcp_url, gcp_icon)

objtree_url = "https://user-images.githubusercontent.com/664179/39915797-245107d6-5509-11e8-82e4-6421456bf7eb.png"
objtree_icon = "/tmp/icon-objtree.png"
urlretrieve(objtree_url, objtree_icon)

DIAGRAMS_PATH="./images"
DIAGRAMS_PREFIX="ocp-oidc-multitenant"
DIAGRAM_BASE_NAME=f"{DIAGRAMS_PATH}/{DIAGRAMS_PREFIX}"


## resizing the banner image to 1200x450
def resize_image(base_fname_png, x, y):
    from PIL import Image, ImageOps
    cur_img = Image.open(f"{base_fname_png}.png")
    size = (x, y)

    # https://pillow.readthedocs.io/en/stable/reference/Image.html#PIL.Image.Image.resize
    res_img = cur_img.resize(size)
    res_img.save(f"{base_fname_png}-{x}x{y}.png")

    # # https://pillow.readthedocs.io/en/stable/reference/ImageOps.html#PIL.ImageOps.fit
    # bleed_perc=0.09
    # fit_img = ImageOps.fit(image=cur_img, size=size, bleed=bleed_perc)
    # fit_img.save(f"{base_fname_png}-fit-{bleed_perc}perc.png")

    # # https://pillow.readthedocs.io/en/stable/reference/ImageOps.html#PIL.ImageOps.crop
    # crop_px=80
    # crop_img = ImageOps.crop(image=res_img, border=crop_px)
    # crop_img.save(f"{base_fname_png}-crop-{crop_px}px.png")

    # # # Size of the image in pixels (size of original image)
    # # (This is not mandatory)
    # width, height = cur_img.size

    # # Setting the points for cropped image
    # left = width / 10
    # top = height / 6
    # right = width / 10
    # bottom = height / 6

    # # Cropped image of above dimension
    # # (It will not change original image)
    # crop2_img = cur_img.crop((left, top, right, bottom))
    # crop2_img.save(f"{base_fname_png}-crop2.png")

#
# Banner
#
graph_attr = {}
DIAGRAM_NAME_BANNER=f"{DIAGRAM_BASE_NAME}-banner.diagram"
with Diagram("OpenShift Authentication mode with STS Overview",
            show=False, filename=DIAGRAM_NAME_BANNER,
            graph_attr=graph_attr):
    dnsIssuerURL = DNSZones("oidc.<base_domain>")
    
    # pvtLinkSTS = Privatelink("STS Endpoint (private or public)")
    with Cluster("Cloud Provider"):
        with Cluster("Provider/IAM_APIs", direction="TB"):
            svcOIDC = Custom("Service_OIDC", api_icon)
            svcSTS = Custom("Service_STS", api_icon)

        # aws = Custom("AWS OCP Cluster", aws_icon)
        # gcp = Custom("GCP OCP Cluster", gcp_icon)

    with Cluster("AWS/Account"):
        cfnOIDC = CF("CloudFront\nDistribution\nhttps://oidc.<base_domain>")
        s3BucketOIDC = SimpleStorageServiceS3BucketWithObjects("oidc.<base_domain>")
        objects = Custom("<clusterId>/", objtree_icon)

    with Cluster("OpenShift/STS"):
        k8s = Custom("Kubernetes", k8s_icon)
        ocp = Custom("OpenShift", openshift_icon)

    svcOIDC >> dnsIssuerURL >> cfnOIDC >> s3BucketOIDC >> objects
    k8s - ocp >> svcSTS
    svcSTS - svcOIDC

resize_image(f"{DIAGRAM_NAME_BANNER}", 1000, 350)

#
# Diagram Overview
#
graph_attr_overview = {
    "margin":"-2, -2"
}
with Diagram("OCP OIDC Multi-tenant on AWS",
            show=False, filename=f"{DIAGRAM_BASE_NAME}-overview.diagram",
            graph_attr=graph_attr_overview):
    
    dnsIssuerURL = DNSZones("oidc.<base_domain>")
    # pvtLinkSTS = Privatelink("STS Endpoint (private or public)")
    with Cluster("AWS/IAM_Services"):
        svcOIDC = Custom("Service_OIDC", api_icon)
        svcSTS = Custom("Service_STS", api_icon)
        

    with Cluster("AWS/Account"):

        with Cluster("AWS/Account/Services"):
            cfnSSL = ACM("SSL Cert")
            with Cluster("AWS/Account/Services/CloudFront"):
                cfnOIDC = CF("CloudFront\nDistribution")
                cfnIdentityS3 = IdentityAndAccessManagementIamAddOn("OAI S3 Bucket")
            
            with Cluster("AWS/Account/Services/S3"):        
                s3BucketOIDC = SimpleStorageServiceS3BucketWithObjects("oidc.<base_domain>")
                oidcConfigC1 = SimpleStorageServiceS3Object("/cluster1-oidc")
                oidcConfigC2 = SimpleStorageServiceS3Object("/clusterN-oidc")
                objects = [
                    oidcConfigC1, oidcConfigC2
                ]

                objFiles = Custom("Objects", files_icon)

        with Cluster("AWS/Account/VPC{1..N}"):
            cluster1 = Custom("cluster{1..N}", openshift_icon)

    dnsIssuerURL >> cfnOIDC >> cfnIdentityS3 >> s3BucketOIDC >> objFiles >> objects
    svcSTS >> svcOIDC >> dnsIssuerURL
    cfnOIDC >> cfnSSL
    # openshift >> pvtLinkSTS >> svcSTS


#
# OCP Expanded
#
with Diagram("OCP K8S signer", show=False, filename=f"{DIAGRAM_BASE_NAME}-flow-k8s.diagram"):

    dnsIssuerURL = DNSZones("oidc.<base_domain>")

    with Cluster("OpenShift"):
        cluster = Custom("cluster1", openshift_icon)
        
        with Cluster("OpenShift/K8S"):

            with Cluster("OpenShift/K8S/RBAC"):
                cr = ClusterRole("system:service-account-issuer-discovery")
                crb = ClusterRoleBinding("default")
                group = Group("system:serviceaccounts")

            with Cluster("OpenShift/K8S/APIserver"):
                kas = APIServer("Kube-API")
                with Cluster("OpenShift/K8S/APIserver/HTTP"):
                    kasOidcConfig = APIServer("/.well-know/openid-configuration")
                    kasOidcJwks = APIServer("/openid/v1/jwks")


            with Cluster("OpenShift/K8S/Namespace"):
                with Cluster("OpenShift/K8S/Namespace/ServiceAccount"):
                    sa = ServiceAccount("ServiceAccount")
                    saToken = GenericSamlToken("SA-Token")
                    saVol = Vol("ProjectedToken")
                pod = Pod("pod")

    kas >> Edge(label="Sign") >> saToken << saVol >> pod
    pod - sa
    sa - group
    cr << cr >> group
    cr >> [kasOidcConfig, kasOidcJwks]

#
# AWS IAM Expanded
#
graph_attr_flowaws = {
    "margin": "-2, -2"
}
with Diagram("OCP Cluster calling OIDC", show=False,
            filename=f"{DIAGRAM_BASE_NAME}-flow-aws.diagram",
            graph_attr=graph_attr_flowaws):

    dnsIssuerURL = DNSZones("oidc.<base_domain>")

    with Cluster("AWS"):

        with Cluster("AWS/Account"):

            with Cluster("AWS/Account/VPC/OpenShift"):
                cluster = Custom("cluster1", openshift_icon)

            pvtLinkSTS = Privatelink("STS Endpoint\n(private or public)")

            with Cluster("AWS/Account/Services"):
            
                with Cluster("AWS/Account/Services/CloudFront"):
                    cfnOIDC = CF("CloudFront Distribution")


        with Cluster("AWS/IAM_Services"):

            with Cluster("AWS/IAM_Services/IdP_OIDC"):
                svcOIDC = Custom("Service_OIDC", api_icon)

            with Cluster("AWS/IAM_Services/STS"):
                svcSTS = Custom("STS_API", api_icon)
                sts = IdentityAndAccessManagementIamAWSStsAlternate("STS")
                stsToken = IdentityAndAccessManagementIamTemporarySecurityCredential("STS_Creds")
                iamRole = IAMRole("IamRoleForService")


        dnsIssuerURL >> cfnOIDC
        svcSTS >> svcOIDC >> dnsIssuerURL
        svcSTS >> sts >> [iamRole, stsToken]
        cluster >> pvtLinkSTS >> svcSTS
