# ==============================================================================
# Azure Networking Resources
# ==============================================================================

# ------------------------------------------------------------------------------
# Virtual Network
# ------------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vpc_cidr]

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Public Subnets
# ------------------------------------------------------------------------------
resource "azurerm_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  name                 = "${var.name_prefix}-public-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidrs[count.index]]
}

# ------------------------------------------------------------------------------
# Private Subnets
# ------------------------------------------------------------------------------
resource "azurerm_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  name                 = "${var.name_prefix}-private-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidrs[count.index]]
}

# ------------------------------------------------------------------------------
# Network Security Group
# ------------------------------------------------------------------------------
resource "azurerm_network_security_group" "main" {
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # SSH Rule
  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_ssh_cidrs
    destination_address_prefix = "*"
  }

  # HTTP Rule
  security_rule {
    name                       = "HTTP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_http_cidrs
    destination_address_prefix = "*"
  }

  # HTTPS Rule
  security_rule {
    name                       = "HTTPS"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_http_cidrs
    destination_address_prefix = "*"
  }

  # Application Port
  security_rule {
    name                       = "AppPort"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.app_port)
    source_address_prefixes    = var.allowed_http_cidrs
    destination_address_prefix = "*"
  }

  # Health Check Port
  security_rule {
    name                       = "HealthCheck"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.health_check_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Outbound Internet
  security_rule {
    name                       = "OutboundInternet"
    priority                   = 400
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = var.common_tags
}

# ------------------------------------------------------------------------------
# Associate NSG with Subnets
# ------------------------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id                 = azurerm_subnet.public[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id                 = azurerm_subnet.private[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

# ------------------------------------------------------------------------------
# NAT Gateway for Private Subnets
# ------------------------------------------------------------------------------
resource "azurerm_public_ip" "nat" {
  name                = "${var.name_prefix}-nat-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.common_tags
}

resource "azurerm_nat_gateway" "main" {
  name                    = "${var.name_prefix}-nat"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = var.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = azurerm_subnet.private[count.index].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
